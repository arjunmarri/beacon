import type { TrafficLightColor } from '../types.ts';

interface TrafficLightLampProps {
  active: TrafficLightColor;
  label: string;
}

export function TrafficLightLamp({ active, label }: TrafficLightLampProps) {
  const labelColor =
    active === 'green'
      ? 'text-emerald-400'
      : active === 'amber'
        ? 'text-amber-400'
        : 'text-rose-400';

  return (
    <div className="flex items-center gap-3 shrink-0" role="status" aria-label={`Status: ${label}`}>
      <div
        className="inline-flex items-center gap-1.5 px-2 py-1.5 rounded-full bg-[#090B0E] border border-white/[0.08] shadow-inner"
        aria-hidden="true"
      >
        <span
          className={`w-2.5 h-2.5 rounded-full transition-all duration-150 ${
            active === 'red'
              ? 'bg-[#EF4444] shadow-[0_0_8px_rgba(239,68,68,0.85)] ring-1 ring-rose-300/40'
              : 'bg-[#2A1719] border border-white/[0.04]'
          }`}
        />
        <span
          className={`w-2.5 h-2.5 rounded-full transition-all duration-150 ${
            active === 'amber'
              ? 'bg-[#F59E0B] shadow-[0_0_8px_rgba(245,158,11,0.85)] ring-1 ring-amber-200/40'
              : 'bg-[#2B2214] border border-white/[0.04]'
          }`}
        />
        <span
          className={`w-2.5 h-2.5 rounded-full transition-all duration-150 ${
            active === 'green'
              ? 'bg-[#22C55E] shadow-[0_0_8px_rgba(34,197,94,0.85)] ring-1 ring-emerald-200/40'
              : 'bg-[#13261B] border border-white/[0.04]'
          }`}
        />
      </div>
      <span className={`text-xs font-semibold tracking-wide whitespace-nowrap ${labelColor}`}>
        {label}
      </span>
    </div>
  );
}
