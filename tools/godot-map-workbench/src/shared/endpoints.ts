export const WORKBENCH_API_PREFIX = "/__godot-map-workbench";
export const DEFAULT_PIXELWORK_ENDPOINT = `${WORKBENCH_API_PREFIX}/default-pixelwork`;
export const LIST_PIXELWORK_ENDPOINT = `${WORKBENCH_API_PREFIX}/pixelwork-packages`;
export const PICK_MAP_SOURCE_FOLDER_ENDPOINT = `${WORKBENCH_API_PREFIX}/pick-map-source-folder`;
export const IMPORT_PIXELWORK_ENDPOINT = `${WORKBENCH_API_PREFIX}/import-pixelwork`;
export const LOAD_MAP_ENDPOINT = `${WORKBENCH_API_PREFIX}/map`;
export const SAVE_MAP_ENDPOINT = `${WORKBENCH_API_PREFIX}/save`;
export const FILE_ENDPOINT = `${WORKBENCH_API_PREFIX}/file`;

export function localFileUrl(assetPath: string): string {
  return `${FILE_ENDPOINT}?path=${encodeURIComponent(assetPath)}`;
}
