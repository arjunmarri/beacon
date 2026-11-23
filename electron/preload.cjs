const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('beaconDesktop', {
  isMacApp: true,
  platform: process.platform,
});
