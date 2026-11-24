.pragma library

// Cute chonky cat vector silhouettes on a 24x18 coordinate grid (running right).
// Five-frame bouncy chonk gallop cycle plus two mega-loaf sleeping frames.
var VIEWBOX_WIDTH = 24
var VIEWBOX_HEIGHT = 18

var RUN_FRAMES = [
  // Frame 0: Chonky leap — round belly lifted, stubby paws stretching out, fluffy tail streaming
  "M 15.2 5.4 Q 16.0 3.0 16.8 1.8 Q 17.7 2.8 18.4 4.0 Q 19.3 3.9 20.0 4.0 Q 20.8 2.6 21.6 2.0 Q 22.2 3.5 22.1 5.4 Q 23.4 6.6 23.2 8.2 Q 22.8 10.0 20.8 10.6 Q 22.2 12.2 23.0 13.4 Q 23.3 14.4 22.2 14.7 Q 21.1 14.9 19.6 13.2 Q 20.6 14.8 20.2 15.6 Q 19.4 16.2 18.4 15.4 L 16.8 13.4 Q 12.4 14.4 8.2 13.4 Q 6.4 15.2 5.0 16.0 Q 3.8 16.2 3.5 15.1 Q 3.4 14.2 5.4 12.4 Q 3.4 13.8 2.4 13.6 Q 1.5 13.2 2.0 12.0 Q 3.4 10.4 4.8 9.4 Q 3.0 8.6 1.4 8.2 Q 0.4 7.7 0.7 6.5 Q 1.1 5.5 2.4 5.9 Q 4.0 6.4 5.6 6.8 Q 8.2 4.6 12.0 4.8 Q 13.8 4.9 15.2 5.4 Z",

  // Frame 1: Front pitter-patter — stubby front paws planted, plump belly low, fluffy tail lifting
  "M 15.0 5.6 Q 15.8 3.2 16.6 2.1 Q 17.5 3.1 18.2 4.3 Q 19.1 4.2 19.8 4.3 Q 20.6 2.9 21.4 2.3 Q 22.0 3.8 21.9 5.7 Q 23.1 6.9 22.9 8.5 Q 22.4 10.3 20.3 10.9 Q 20.8 13.6 20.8 15.8 Q 20.6 16.9 19.3 16.9 Q 18.2 16.9 18.0 15.4 L 17.8 13.6 Q 17.6 15.2 17.2 16.2 Q 16.6 17.0 15.5 16.7 Q 14.6 16.3 14.8 14.6 L 14.9 13.8 Q 11.8 14.6 8.4 13.7 Q 7.4 15.2 6.6 16.3 Q 5.7 17.0 4.7 16.4 Q 4.0 15.8 4.8 14.2 L 5.6 12.6 Q 4.2 14.0 3.4 14.4 Q 2.4 14.6 2.2 13.4 Q 2.2 12.4 4.6 10.0 Q 4.4 8.2 5.2 7.2 Q 3.2 6.2 1.8 4.8 Q 1.1 3.8 2.0 3.0 Q 2.9 2.4 3.9 3.5 Q 5.0 4.8 6.4 5.9 Q 9.0 4.6 12.2 4.9 Q 13.8 5.0 15.0 5.6 Z",

  // Frame 2: Squishy gathered bounce — maximum round chonk, arched back, paws tucked snugly, happy curled tail
  "M 14.2 4.6 Q 15.0 2.3 15.8 1.3 Q 16.7 2.3 17.4 3.5 Q 18.3 3.4 19.0 3.5 Q 19.8 2.1 20.6 1.6 Q 21.2 3.1 21.1 4.9 Q 22.4 6.2 22.2 7.9 Q 21.8 9.8 19.6 10.5 Q 19.2 13.2 18.2 15.8 Q 17.6 16.9 16.4 16.7 Q 15.4 16.5 15.6 15.0 L 16.0 13.2 Q 15.0 15.0 14.2 15.8 Q 13.4 16.4 12.5 15.8 Q 11.9 15.2 12.6 13.6 Q 11.8 13.8 11.0 13.6 Q 11.6 15.2 11.4 16.2 Q 11.0 17.1 9.8 16.9 Q 8.8 16.7 8.6 15.2 L 8.2 13.2 Q 7.6 15.0 7.0 15.8 Q 6.2 16.5 5.4 15.7 Q 4.8 15.0 5.4 13.2 Q 4.6 11.4 4.8 9.2 Q 5.0 7.4 5.8 6.2 Q 4.0 4.8 3.2 3.0 Q 2.8 1.8 4.0 1.4 Q 5.1 1.1 5.6 2.4 Q 6.2 3.8 7.2 4.8 Q 9.6 3.4 12.2 3.9 Q 13.3 4.1 14.2 4.6 Z",

  // Frame 3: Booty push-off — plump body springing up, front stubby paws lifting, back paws pushing off
  "M 15.0 4.8 Q 15.8 2.4 16.6 1.3 Q 17.5 2.4 18.2 3.6 Q 19.1 3.5 19.8 3.6 Q 20.6 2.2 21.4 1.6 Q 22.0 3.1 21.9 5.0 Q 23.2 6.2 23.0 7.9 Q 22.5 9.7 20.5 10.3 Q 21.8 11.8 22.6 12.8 Q 23.0 13.8 21.9 14.3 Q 20.8 14.7 19.6 13.2 L 18.6 12.2 Q 19.4 13.8 19.0 14.8 Q 18.4 15.6 17.3 15.0 L 16.0 13.3 Q 12.4 14.2 9.0 13.6 Q 8.6 15.4 8.2 16.4 Q 7.6 17.2 6.5 16.9 Q 5.5 16.6 5.8 15.0 L 6.2 13.0 Q 5.0 15.0 4.2 16.0 Q 3.4 16.6 2.5 15.9 Q 1.8 15.2 2.8 13.6 L 4.8 10.4 Q 4.6 8.4 5.2 7.2 Q 3.0 6.6 1.6 5.6 Q 0.8 4.8 1.4 3.8 Q 2.1 2.9 3.3 3.7 Q 4.6 4.6 6.2 5.6 Q 8.8 4.2 12.2 4.3 Q 13.8 4.4 15.0 4.8 Z",

  // Frame 4: Happy mid-bound — plump round belly gliding forward, stubby paws cycling wide
  "M 15.4 5.2 Q 16.2 2.8 17.0 1.7 Q 17.9 2.7 18.6 3.9 Q 19.5 3.8 20.2 3.9 Q 21.0 2.5 21.8 1.9 Q 22.4 3.4 22.3 5.3 Q 23.5 6.5 23.3 8.1 Q 22.8 9.9 20.8 10.5 Q 22.0 12.6 22.6 14.2 Q 22.7 15.3 21.6 15.6 Q 20.4 15.8 19.4 14.0 L 18.4 12.8 Q 19.2 14.8 18.8 15.8 Q 18.0 16.6 17.0 15.8 L 15.8 13.6 Q 12.0 14.5 8.0 13.6 Q 6.4 15.4 5.2 16.3 Q 4.1 16.7 3.6 15.6 Q 3.3 14.6 4.8 12.8 L 5.4 12.0 Q 3.6 13.8 2.6 14.2 Q 1.6 14.3 1.5 13.1 Q 1.6 12.1 4.4 9.6 Q 4.6 8.2 5.0 7.4 Q 3.0 7.8 1.4 7.6 Q 0.4 7.3 0.6 6.1 Q 0.9 5.0 2.2 5.3 Q 3.8 5.6 5.6 6.3 Q 8.4 4.5 12.2 4.7 Q 13.9 4.8 15.4 5.2 Z"
]

var SLEEP_FRAMES = [
  // Extra-plump curled cat loaf (exhale)
  "M 2.4 14.6 Q 1.8 8.4 8.6 6.8 Q 12.4 6.0 14.6 7.8 L 15.4 4.8 Q 16.4 5.6 17.0 6.8 Q 17.8 6.7 18.4 6.8 L 19.4 5.0 Q 20.4 6.2 20.4 8.0 Q 22.2 10.0 21.6 13.8 Q 20.8 16.6 17.6 16.6 L 5.6 16.6 Q 2.8 16.6 2.4 14.6 Z",
  // Extra-plump curled cat loaf (gentle inhale)
  "M 2.4 14.6 Q 1.6 7.4 8.6 5.8 Q 12.6 5.0 14.7 7.2 L 15.5 4.2 Q 16.5 5.0 17.1 6.2 Q 17.9 6.1 18.5 6.2 L 19.5 4.4 Q 20.5 5.6 20.5 7.6 Q 22.2 9.6 21.6 13.8 Q 20.8 16.6 17.6 16.6 L 5.6 16.6 Q 2.8 16.6 2.4 14.6 Z"
]

var SLEEP_Z_FRAMES = [
  "M 18.8 2.2 L 22.0 2.2 L 18.8 4.8 L 22.0 4.8",
  "M 19.6 1.2 L 22.8 1.2 L 19.6 3.8 L 22.8 3.8"
]

// Tiny celebratory crown perched between the ears of the current #1 leader.
var CROWN_PATH = "M 16.9 2.4 L 17.3 0.5 L 18.4 1.6 L 19.2 0.2 L 20.0 1.6 L 21.1 0.5 L 21.5 2.4 Z"

// Distinct subtle coat markings / accessories for each gang member (running poses).
var VARIANT_MARKINGS = {
  // Tabby stripes across the plump back
  tabby: "M 9.6 5.6 L 10.3 8.8 M 11.7 5.4 L 12.3 8.9 M 13.8 5.7 L 14.3 8.8",
  // Sleek cyber visor across the eyes
  visor: "M 18.4 6.6 L 22.4 6.8",
  // Tuxedo collar & chest stripe
  tuxedo: "M 15.4 8.2 Q 17.2 9.4 19.2 9.6",
  // Calico cute saddle spot on back
  calico: "M 8.8 6.4 Q 11.2 5.4 13.4 6.6 Q 12.6 9.2 9.8 9.0 Z",
  // Speedy lightning bolt on flank
  bolt: "M 11.8 6.2 L 9.8 8.7 L 11.7 8.7 L 10.2 11.2"
}

// Speed streaks trailing behind sprinting cats (alternates slightly per frame).
var SPEED_STREAK_FRAMES = [
  "M -2.2 6.8 L 0.5 6.8 M -3.6 9.8 L -0.4 9.8 M -1.8 12.4 L 0.6 12.4",
  "M -3.4 6.4 L -0.2 6.4 M -2.0 9.6 L 0.6 9.6 M -3.2 12.8 L -0.4 12.8"
]

function pathFor(frameIndex, sleeping) {
  var list = sleeping ? SLEEP_FRAMES : RUN_FRAMES
  var idx = ((Math.floor(frameIndex) % list.length) + list.length) % list.length
  return list[idx]
}

function sleepZPath(frameIndex) {
  var idx = ((Math.floor(frameIndex) % SLEEP_Z_FRAMES.length) + SLEEP_Z_FRAMES.length) % SLEEP_Z_FRAMES.length
  return SLEEP_Z_FRAMES[idx]
}

function markingPath(variant, sleeping) {
  if (sleeping || !variant) return ""
  return VARIANT_MARKINGS[variant] || ""
}

function isFilledMarking(variant) {
  return variant === "calico"
}

function speedStreakPath(frameIndex) {
  var idx = ((Math.floor(frameIndex) % SPEED_STREAK_FRAMES.length) + SPEED_STREAK_FRAMES.length) % SPEED_STREAK_FRAMES.length
  return SPEED_STREAK_FRAMES[idx]
}
