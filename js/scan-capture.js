export const CROP_PROFILES = {
  square: {
    id: 'square',
    label: 'Vuông',
    widthRatio: 0.72,
    heightRatio: 0.72,
  },
  wide: {
    id: 'wide',
    label: 'Ngang',
    widthRatio: 0.9,
    heightRatio: 0.52,
  },
  tall: {
    id: 'tall',
    label: 'Dọc',
    widthRatio: 0.52,
    heightRatio: 0.9,
  },
  full: {
    id: 'full',
    label: 'Toàn khung',
    widthRatio: 0.96,
    heightRatio: 0.96,
  },
};

export const ZOOM_LEVELS = [1, 2, 4];

export function captureVideoFrame(video, context, canvas, {
  zoom = 1,
  cropProfile = 'square',
} = {}) {
  const profile = CROP_PROFILES[cropProfile] ?? CROP_PROFILES.square;
  const sourceWidth = video.videoWidth;
  const sourceHeight = video.videoHeight;
  const zoomFactor = Math.max(1, zoom);

  const cropWidth = (sourceWidth * profile.widthRatio) / zoomFactor;
  const cropHeight = (sourceHeight * profile.heightRatio) / zoomFactor;
  const cropX = (sourceWidth - cropWidth) / 2;
  const cropY = (sourceHeight - cropHeight) / 2;

  canvas.width = Math.round(cropWidth * zoomFactor);
  canvas.height = Math.round(cropHeight * zoomFactor);
  context.imageSmoothingEnabled = zoomFactor > 1;
  context.drawImage(
    video,
    cropX,
    cropY,
    cropWidth,
    cropHeight,
    0,
    0,
    canvas.width,
    canvas.height,
  );

  return canvas;
}

export function getCropProfileList(mode = 'auto') {
  if (mode === 'square') return ['square'];
  if (mode === 'wide') return ['wide'];
  if (mode === 'tall') return ['tall'];
  return ['square', 'wide', 'tall', 'full'];
}

export function buildScanCombinations({
  mode = 'hard',
  cropMode = 'auto',
  zoomLevel = 1,
  pipelineNames,
}) {
  const crops = getCropProfileList(cropMode);
  const zooms = [Math.max(1, zoomLevel)];
  const combinations = [];

  for (const crop of crops) {
    for (const zoom of zooms) {
      for (const pipeline of pipelineNames) {
        combinations.push({ crop, zoom, pipeline, raw: false });
      }
      combinations.push({ crop, zoom, pipeline: null, raw: true });
    }
  }

  return combinations;
}

export function createScanScheduler({
  mode = 'hard',
  cropMode = 'auto',
  zoomLevel = 1,
  pipelineNames,
}) {
  const combinations = buildScanCombinations({ mode, cropMode, zoomLevel, pipelineNames });
  let index = 0;
  let preferredIndex = -1;

  return {
    next() {
      if (preferredIndex >= 0) {
        const preferred = combinations[preferredIndex];
        preferredIndex = -1;
        return preferred;
      }

      const current = combinations[index % combinations.length];
      index += 1;
      return current;
    },
    markSuccess(combination) {
      const foundIndex = combinations.findIndex(
        (item) =>
          item.crop === combination.crop &&
          item.zoom === combination.zoom &&
          item.pipeline === combination.pipeline &&
          item.raw === combination.raw,
      );
      if (foundIndex >= 0) {
        preferredIndex = foundIndex;
      }
    },
    reset() {
      index = 0;
      preferredIndex = -1;
    },
    get size() {
      return combinations.length;
    },
  };
}
