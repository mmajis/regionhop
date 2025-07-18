import * as fs from 'fs';
import * as path from 'path';

export interface RegionInfo {
  code: string;
  name: string;
  description: string;
}

export interface RegionConfig {
  supportedRegions: RegionInfo[];
  defaultRegion: string;
  vpnSubnet: string;
  vpnPort: number;
}

let regionConfig: RegionConfig | null = null;

/**
 * Load region configuration from regions.json
 */
function loadRegionConfig(): RegionConfig {
  if (!regionConfig) {
    const configPath = path.join(__dirname, '..', 'regions.json');
    const configData = fs.readFileSync(configPath, 'utf8');
    regionConfig = JSON.parse(configData);
  }
  return regionConfig!;
}

/**
 * Get all supported regions
 */
export function getSupportedRegions(): RegionInfo[] {
  return loadRegionConfig().supportedRegions;
}

/**
 * Get the default region
 */
export function getDefaultRegion(): string {
  return loadRegionConfig().defaultRegion;
}

/**
 * Get VPN subnet configuration
 */
export function getVpnSubnet(): string {
  return loadRegionConfig().vpnSubnet;
}

/**
 * Get VPN port configuration
 */
export function getVpnPort(): number {
  return loadRegionConfig().vpnPort;
}

/**
 * Validate if a region is supported
 */
export function isRegionSupported(region: string): boolean {
  const supportedRegions = getSupportedRegions();
  return supportedRegions.some(r => r.code === region);
}

/**
 * Get region from environment variable or default
 */
export function getTargetRegion(): string {
  const envRegion = process.env.VPN_REGION;
  if (envRegion) {
    if (!isRegionSupported(envRegion)) {
      throw new Error(`Unsupported region: ${envRegion}. Supported regions: ${getSupportedRegions().map(r => r.code).join(', ')}`);
    }
    return envRegion;
  }
  return getDefaultRegion();
}

/**
 * Get region-aware stack name
 */
export function getStackName(baseName: string, region: string): string {
  return `OwnVPN-${region}-${baseName}`;
}

/**
 * Get region-aware export name
 */
export function getExportName(baseName: string, region: string): string {
  return `OwnVPN-${region}-${baseName}`;
}

/**
 * Get region-aware resource name
 */
export function getResourceName(baseName: string, region: string): string {
  return `${baseName}-${region}`;
}

/**
 * Get region info by code
 */
export function getRegionInfo(regionCode: string): RegionInfo | undefined {
  return getSupportedRegions().find(r => r.code === regionCode);
}

/**
 * Validate region and throw error if not supported
 */
export function validateRegion(region: string): void {
  if (!isRegionSupported(region)) {
    const supportedRegions = getSupportedRegions().map(r => r.code).join(', ');
    throw new Error(`Unsupported region: ${region}. Supported regions: ${supportedRegions}`);
  }
}