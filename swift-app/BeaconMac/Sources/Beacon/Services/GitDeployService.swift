import Foundation

public struct GitAccountVerification: Sendable {
    public let username: String
    public let repos: [GitRepoSummary]
}

public struct GitCommitSnapshot: Sendable {
    public let shaShort: String
    public let message: String
}

/// App-Sandbox-native GitHub API client + NSUserUnixTask local `git pull` bridge.
public final class GitDeployService: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        self.session = URLSession(configuration: config)
    }

    public func verifyTokenAndFetchRepos(token: String) async throws -> GitAccountVerification {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanToken.count >= 10, !cleanToken.contains(where: \.isWhitespace) else {
            throw NSError(domain: "BeaconGit", code: 400, userInfo: [NSLocalizedDescriptionKey: "Enter a valid GitHub Personal Access Token."])
        }

        var userReq = URLRequest(url: URL(string: "https://api.github.com/user")!)
        userReq.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        userReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        userReq.setValue("Beacon-Mac-Swift", forHTTPHeaderField: "User-Agent")

        let (userData, userResp) = try await session.data(for: userReq)
        guard let http = userResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (userResp as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "BeaconGit", code: code, userInfo: [NSLocalizedDescriptionKey: "GitHub authentication failed (HTTP \(code)). Check token scopes."])
        }

        struct GHUser: Decodable { let login: String }
        let user = try JSONDecoder().decode(GHUser.self, from: userData)

        var repos: [GitRepoSummary] = []
        var reposReq = URLRequest(url: URL(string: "https://api.github.com/user/repos?sort=updated&per_page=40&affiliation=owner,collaborator,organization_member")!)
        reposReq.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        reposReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        reposReq.setValue("Beacon-Mac-Swift", forHTTPHeaderField: "User-Agent")

        if let (repoData, repoResp) = try? await session.data(for: reposReq),
           let repoHTTP = repoResp as? HTTPURLResponse, (200...299).contains(repoHTTP.statusCode) {
            struct GHRepo: Decodable {
                let full_name: String
                let clone_url: String
                let default_branch: String?
                let `private`: Bool?
            }
            if let decoded = try? JSONDecoder().decode([GHRepo].self, from: repoData) {
                repos = decoded.map {
                    GitRepoSummary(
                        fullName: $0.full_name,
                        cloneURL: $0.clone_url,
                        defaultBranch: $0.default_branch ?? "main",
                        isPrivate: $0.private ?? false
                    )
                }
            }
        }

        return GitAccountVerification(username: user.login, repos: repos)
    }

    public func fetchLatestCommit(repoFullName: String, branch: String, token: String?) async throws -> GitCommitSnapshot {
        let cleanRepo = repoFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanRepo.contains("/"), !cleanBranch.isEmpty,
              let encodedBranch = cleanBranch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/repos/\(cleanRepo)/commits/\(encodedBranch)") else {
            throw NSError(domain: "BeaconGit", code: 400, userInfo: [NSLocalizedDescriptionKey: "Specify repository as owner/repo and a valid branch name."])
        }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Beacon-Mac-Swift", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "BeaconGit", code: code, userInfo: [NSLocalizedDescriptionKey: "Could not read \(cleanRepo)@\(cleanBranch) (HTTP \(code))."])
        }

        struct GHCommitResponse: Decodable {
            struct InnerCommit: Decodable { let message: String }
            let sha: String
            let commit: InnerCommit
        }
        let decoded = try JSONDecoder().decode(GHCommitResponse.self, from: data)
        let firstLine = decoded.commit.message.split(separator: "\n").first.map(String.init) ?? decoded.commit.message
        return GitCommitSnapshot(shaShort: String(decoded.sha.prefix(7)), message: firstLine)
    }

    /// Executes `~/Library/Application Scripts/<bundle-id>/beacon-git-pull.sh`
    /// via Apple's App-Sandbox-approved NSUserUnixTask API.
    public func runSandboxGitPullScript(workingDir: String, branch: String) async -> (ok: Bool, detail: String) {
        guard let scriptsDir = try? FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return (false, "Application Scripts folder unavailable.")
        }

        let scriptURL = scriptsDir.appendingPathComponent("beacon-git-pull.sh")

        do {
            // Never gate on FileManager.fileExists(atPath:) inside macOS App Sandbox:
            // Sandbox denies POSIX stat() on ~/Library/Application Scripts/<bundle-id>/.
            let task = try NSUserUnixTask(url: scriptURL)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.execute(withArguments: [workingDir, branch]) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            return (true, "Pulled latest changes on branch \(branch) via beacon-git-pull.sh.")
        } catch {
            let nsErr = error as NSError
            let isMissing = nsErr.domain == NSCocoaErrorDomain && (
                nsErr.code == NSFileReadNoSuchFileError ||
                nsErr.code == NSFileNoSuchFileError
            )
            if isMissing {
                return (
                    false,
                    "Remote commit detected. Click \"Install Hook Scripts\" or install beacon-git-pull.sh in ~/Library/Application Scripts/\(EmbeddedScripts.bundleID)/ to pull automatically."
                )
            }
            return (false, "Git pull script failed: \(error.localizedDescription)")
        }
    }
}
