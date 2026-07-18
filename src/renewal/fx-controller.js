import { cardFramePath, enhancementLabel, enhancementTier } from './card-visual.js';

const OUTCOME_COLORS = {
  success: ['#d7ff35', '#68f7ef', '#ffffff'],
  fail: ['#e5bd4e', '#ff9b3f', '#ffffff'],
  destroy: ['#ff455d', '#ff8a45', '#ffffff'],
};

const RARITY_CINEMATICS = Object.freeze({
  S: { duration: 5000, mp4: 'assets/renewal/fx/rarity-s.mp4', webm: 'assets/renewal/fx/rarity-s.webm', audio: 'assets/renewal/fx/rarity-s.mp3' },
  SS: { duration: 6000, mp4: 'assets/renewal/fx/rarity-ss.mp4', webm: 'assets/renewal/fx/rarity-ss.webm', audio: 'assets/renewal/fx/rarity-ss.mp3' },
  SSS: { duration: 6000, mp4: 'assets/renewal/fx/rarity-sss.mp4', webm: 'assets/renewal/fx/rarity-sss.webm', audio: 'assets/renewal/fx/rarity-sss.mp3' },
});

const CINEMATIC_RARITIES = ['S', 'SS', 'SSS'];
const PACK_FAST_FORWARD_PHASES = new Set(['pack-prepare', 'pack-approach', 'pack-charge', 'pack-burst', 'pack-rarity']);

export function canFastForwardPackPhase(phase) {
  return PACK_FAST_FORWARD_PHASES.has(phase);
}

export function highestCinematicRarity(cards) {
  return cards.reduce((highest, card) => {
    const currentRank = CINEMATIC_RARITIES.indexOf(card.rarity);
    const highestRank = CINEMATIC_RARITIES.indexOf(highest);
    return currentRank > highestRank ? card.rarity : highest;
  }, null);
}

export function selectRarityCinematic(cards, reducedMotion = false) {
  if (reducedMotion) return null;
  const rarity = highestCinematicRarity(cards);
  return rarity ? { rarity, ...RARITY_CINEMATICS[rarity] } : null;
}

export function requiresManualPackReveal(cards) {
  return Boolean(highestCinematicRarity(cards));
}

export function enhancementTimeline(outcome, reducedMotion = false) {
  if (reducedMotion) return [
    { phase: 'impact', duration: 40 },
    { phase: 'result', duration: 180 },
  ];
  if (outcome === 'success') return [
    { phase: 'charge', duration: 900 },
    { phase: 'impact', duration: 220 },
    { phase: 'result', duration: 1450 },
    { phase: 'settle', duration: 550 },
  ];
  return [
    { phase: 'charge', duration: 650 },
    { phase: 'impact', duration: 170 },
    { phase: 'result', duration: outcome === 'fail' ? 650 : 950 },
    { phase: 'settle', duration: 220 },
  ];
}

export function enhancementFxTier(target) {
  const level = Math.max(1, Math.min(9, Number(target) || 1));
  if (level === 9) return 'max';
  if (level >= 7) return 'elite';
  if (level >= 4) return 'advanced';
  return 'standard';
}

export function packOpeningTimeline(revealCount, reducedMotion = false) {
  if (reducedMotion) return {
    approach: 30,
    charge: 30,
    burst: 30,
    reveal: 20,
    summary: 100,
  };
  return {
    approach: 480,
    charge: 560,
    burst: 220,
    reveal: revealCount > 5 ? 95 : 150,
    summary: 520,
  };
}

export function selectPackRevealCards(cards, limit = 10) {
  if (cards.length <= limit) return [...cards];
  return cards
    .map((card, index) => ({ ...card, drawIndex: index }))
    .sort((a, b) => b.rank - a.rank || a.drawIndex - b.drawIndex)
    .slice(0, limit);
}

export function selectManualPackRevealCards(cards, limit = 10) {
  return selectPackRevealCards(
    cards.filter((card) => CINEMATIC_RARITIES.includes(card.rarity)),
    limit,
  );
}

export function createFxController({ root = document.getElementById('fxLayer'), soundEnabled = true, random } = {}) {
  if (typeof random !== 'function') throw new Error('FX random adapter is required.');
  if (!root) throw new Error('FX layer not found');

  const cardImage = root.querySelector('[data-fx-card-image]');
  const frameImage = root.querySelector('[data-fx-frame]');
  const rarityLabel = root.querySelector('[data-fx-rarity]');
  const cardName = root.querySelector('[data-fx-card-name]');
  const levelLabel = root.querySelector('[data-fx-level]');
  const levelBurst = root.querySelector('[data-fx-level-burst]');
  const verdict = root.querySelector('[data-fx-verdict]');
  const skipButton = root.querySelector('[data-fx-skip]');
  const canvas = root.querySelector('canvas');
  const packImages = root.querySelectorAll('[data-fx-pack-image]');
  const packName = root.querySelector('[data-fx-pack-name]');
  const revealGrid = root.querySelector('[data-fx-reveal-grid]');
  const revealSummary = root.querySelector('[data-fx-reveal-summary]');
  const revealAllButton = root.querySelector('[data-fx-reveal-all]');
  const rarityVideo = root.querySelector('[data-fx-rarity-video]');
  const context = canvas.getContext('2d');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  const audioBuffers = new Map();
  let active = false;
  let skipAllowed = false;
  let waiting = null;
  let advanceWaiting = null;
  let packFastForwardRequested = false;
  let particleFrame = 0;
  let audioContext = null;
  let activeAudioSource = null;
  let soundOn = soundEnabled;

  function resizeCanvas() {
    const rect = root.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    canvas.width = Math.max(1, Math.round(rect.width * dpr));
    canvas.height = Math.max(1, Math.round(rect.height * dpr));
    canvas.style.width = `${rect.width}px`;
    canvas.style.height = `${rect.height}px`;
    context.setTransform(dpr, 0, 0, dpr, 0, 0);
    return rect;
  }

  function clearParticles() {
    cancelAnimationFrame(particleFrame);
    particleFrame = 0;
    context.clearRect(0, 0, canvas.width, canvas.height);
  }

  function burstParticles(outcome, intensity = 'full', power = 1) {
    clearParticles();
    const rect = resizeCanvas();
    const colors = OUTCOME_COLORS[outcome] ?? OUTCOME_COLORS.fail;
    const restrained = intensity === 'restrained';
    const celebration = intensity === 'celebration';
    const baseCount = celebration ? (rect.width < 900 ? 96 : 156) : restrained ? (rect.width < 900 ? 36 : 64) : (rect.width < 900 ? 70 : 130);
    const count = reducedMotion.matches ? 0 : Math.min(190, Math.round(baseCount * power));
    const particles = Array.from({ length: count }, (_, index) => {
      const angle = (Math.PI * 2 * index) / Math.max(1, count) + (random() - .5) * .35;
      const speed = celebration ? 160 + random() * 430 : restrained ? 65 + random() * 155 : 100 + random() * (outcome === 'destroy' ? 430 : 330);
      return {
        x: rect.width / 2,
        y: rect.height / 2,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        size: celebration ? 1.2 + random() * 4.2 : restrained ? .7 + random() * 1.3 : 1 + random() * 3.5,
        life: celebration ? .8 + random() * .75 : .55 + random() * .55,
        streak: celebration ? 4.5 + random() * 5.5 : restrained ? 2 : 3.5,
        color: colors[index % colors.length],
      };
    });
    const started = performance.now();
    const draw = (now) => {
      const elapsed = (now - started) / 1000;
      context.clearRect(0, 0, rect.width, rect.height);
      particles.forEach((particle) => {
        const progress = elapsed / particle.life;
        if (progress >= 1) return;
        const alpha = 1 - progress;
        const x = particle.x + particle.vx * elapsed;
        const y = particle.y + particle.vy * elapsed + (restrained ? 35 : 90) * elapsed * elapsed;
        context.globalAlpha = alpha;
        context.fillStyle = particle.color;
        context.shadowColor = particle.color;
        context.shadowBlur = celebration ? 18 : 10;
        context.save();
        context.translate(x, y);
        context.rotate(Math.atan2(particle.vy, particle.vx) + Math.PI / 2);
        context.fillRect(0, 0, particle.size * (1 - progress * .45), particle.size * particle.streak);
        context.restore();
      });
      context.globalAlpha = 1;
      context.shadowBlur = 0;
      if (particles.some((particle) => elapsed < particle.life)) particleFrame = requestAnimationFrame(draw);
    };
    particleFrame = requestAnimationFrame(draw);
  }

  function pause(duration) {
    return new Promise((resolve) => {
      let settled = false;
      const complete = (completed) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timer);
        waiting = null;
        advanceWaiting = null;
        resolve(completed);
      };
      const timer = window.setTimeout(() => complete(true), duration);
      waiting = () => complete(false);
      advanceWaiting = () => complete(true);
    });
  }

  function videoSources(cinematic) {
    const mp4Supported = rarityVideo?.canPlayType('video/mp4; codecs="avc1.42E01E, mp4a.40.2"');
    return mp4Supported
      ? [cinematic.mp4, cinematic.webm]
      : [cinematic.webm, cinematic.mp4];
  }

  function unlockAudio() {
    if (!soundOn || !AudioContextClass) return;
    if (!audioContext) audioContext = new AudioContextClass();
    if (audioContext.state === 'suspended') audioContext.resume().catch(() => {});
  }

  function tone({ from, to = from, duration = .12, gain = .035, delay = 0, type = 'sine' }) {
    if (!soundOn || audioContext?.state !== 'running') return;
    const start = audioContext.currentTime + delay;
    const oscillator = audioContext.createOscillator();
    const volume = audioContext.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(Math.max(20, from), start);
    oscillator.frequency.exponentialRampToValueAtTime(Math.max(20, to), start + duration);
    volume.gain.setValueAtTime(.0001, start);
    volume.gain.exponentialRampToValueAtTime(gain, start + Math.min(.025, duration * .2));
    volume.gain.exponentialRampToValueAtTime(.0001, start + duration);
    oscillator.connect(volume).connect(audioContext.destination);
    oscillator.start(start);
    oscillator.stop(start + duration + .02);
  }

  function noise({ duration = .12, gain = .04, frequency = 1800, delay = 0 }) {
    if (!soundOn || audioContext?.state !== 'running') return;
    const frameCount = Math.max(1, Math.floor(audioContext.sampleRate * duration));
    const buffer = audioContext.createBuffer(1, frameCount, audioContext.sampleRate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < frameCount; index += 1) data[index] = (random() * 2 - 1) * (1 - index / frameCount);
    const source = audioContext.createBufferSource();
    const filter = audioContext.createBiquadFilter();
    const volume = audioContext.createGain();
    const start = audioContext.currentTime + delay;
    source.buffer = buffer;
    filter.type = 'bandpass';
    filter.frequency.value = frequency;
    filter.Q.value = .8;
    volume.gain.setValueAtTime(gain, start);
    volume.gain.exponentialRampToValueAtTime(.0001, start + duration);
    source.connect(filter).connect(volume).connect(audioContext.destination);
    source.start(start);
  }

  function playCue(name, rarity = 'F', strength = 1) {
    if (!soundOn) return;
    unlockAudio();
    if (audioContext?.state === 'suspended') {
      audioContext.resume().then(() => playCue(name, rarity)).catch(() => {});
      return;
    }
    const rarityRank = Math.max(0, ['F', 'E', 'D', 'C', 'B', 'A', 'S', 'SS', 'SSS'].indexOf(rarity));
    if (name === 'toggle') {
      tone({ from: 620, to: 880, duration: .1, gain: .035, type: 'triangle' });
    } else if (name === 'pack-approach') {
      tone({ from: 88, to: 148, duration: .42, gain: .045, type: 'sawtooth' });
      noise({ duration: .32, gain: .018, frequency: 720 });
    } else if (name === 'pack-charge') {
      tone({ from: 170, to: 620, duration: .52, gain: .04, type: 'triangle' });
      tone({ from: 340, to: 920, duration: .38, gain: .018, delay: .14, type: 'sine' });
    } else if (name === 'pack-burst') {
      noise({ duration: .2, gain: .09, frequency: 1450 });
      tone({ from: 130, to: 42, duration: .24, gain: .09, type: 'sine' });
    } else if (name === 'card-flip') {
      const base = 560 + rarityRank * 48;
      noise({ duration: .055, gain: .018 + rarityRank * .0015, frequency: 2600 + rarityRank * 120 });
      tone({ from: base, to: base * 1.42, duration: .09, gain: .025 + rarityRank * .002, type: 'triangle' });
    } else if (name === 'pack-summary') {
      tone({ from: 440, to: 660, duration: .16, gain: .035, type: 'sine' });
      tone({ from: 660, to: 990, duration: .18, gain: .025, delay: .09, type: 'sine' });
    } else if (name === 'enhance-charge') {
      tone({ from: 72, to: 260, duration: .62, gain: .05, type: 'sawtooth' });
      tone({ from: 210, to: 760, duration: .48, gain: .018, delay: .12, type: 'triangle' });
    } else if (name === 'enhance-success') {
      noise({ duration: .18, gain: .065 * strength, frequency: 2600 });
      tone({ from: 118, to: 48, duration: .28, gain: .095 * strength, type: 'sine' });
      tone({ from: 390, to: 780, duration: .3, gain: .06 * strength, type: 'triangle' });
      tone({ from: 660, to: 1320, duration: .38, gain: .042 * strength, delay: .08, type: 'sine' });
      tone({ from: 990, to: 1480, duration: .42, gain: .028 * strength, delay: .2, type: 'sine' });
    } else if (name === 'enhance-fail') {
      tone({ from: 210, to: 82, duration: .34, gain: .055, type: 'square' });
      noise({ duration: .16, gain: .025, frequency: 520, delay: .05 });
    } else if (name === 'enhance-destroy') {
      noise({ duration: .42, gain: .11, frequency: 880 });
      tone({ from: 118, to: 28, duration: .55, gain: .12, type: 'sawtooth' });
      tone({ from: 54, to: 24, duration: .62, gain: .08, delay: .08, type: 'square' });
    }
  }

  function setSoundEnabled(enabled) {
    soundOn = Boolean(enabled);
    if (!soundOn) {
      stopRarityAudio();
      if (audioContext?.state === 'running') audioContext.suspend().catch(() => {});
    }
  }

  function prepareRarityAudio(cinematic) {
    if (!soundOn || !audioContext || !cinematic?.audio) return null;
    if (!audioBuffers.has(cinematic.audio)) {
      const buffer = fetch(cinematic.audio)
        .then((response) => {
          if (!response.ok) throw new Error(`FX audio ${response.status}`);
          return response.arrayBuffer();
        })
        .then((data) => audioContext.decodeAudioData(data))
        .catch(() => null);
      audioBuffers.set(cinematic.audio, buffer);
    }
    return audioBuffers.get(cinematic.audio);
  }

  function stopRarityAudio() {
    if (!activeAudioSource) return;
    try { activeAudioSource.stop(); } catch {}
    activeAudioSource = null;
  }

  function startRarityAudio(cinematic) {
    stopRarityAudio();
    const bufferPromise = prepareRarityAudio(cinematic);
    if (!soundOn || !bufferPromise) return;
    bufferPromise.then((buffer) => {
      if (!buffer || !active || root.dataset.phase !== 'pack-rarity' || audioContext?.state !== 'running') return;
      const source = audioContext.createBufferSource();
      const gain = audioContext.createGain();
      source.buffer = buffer;
      gain.gain.value = .82;
      source.connect(gain).connect(audioContext.destination);
      source.onended = () => {
        if (activeAudioSource === source) activeAudioSource = null;
      };
      const offset = Math.min(rarityVideo.currentTime, Math.max(0, buffer.duration - .05));
      source.start(0, offset);
      activeAudioSource = source;
    });
  }

  function prepareRarityVideo(cinematic) {
    if (!rarityVideo || !cinematic) return;
    const [primary, fallback] = videoSources(cinematic);
    rarityVideo.dataset.primary = primary;
    rarityVideo.dataset.fallback = fallback;
    rarityVideo.src = primary;
    rarityVideo.preload = 'auto';
    rarityVideo.load();
    prepareRarityAudio(cinematic);
  }

  function resetRarityVideo(unload = false) {
    if (!rarityVideo) return;
    rarityVideo.pause();
    stopRarityAudio();
    rarityVideo.hidden = true;
    rarityVideo.muted = true;
    if (unload) {
      rarityVideo.removeAttribute('src');
      delete rarityVideo.dataset.primary;
      delete rarityVideo.dataset.fallback;
      rarityVideo.load();
    }
  }

  function playRarityVideo(cinematic) {
    if (!rarityVideo || !cinematic) return Promise.resolve(true);
    root.dataset.phase = 'pack-rarity';
    rarityVideo.hidden = false;
    rarityVideo.currentTime = 0;
    rarityVideo.muted = true;
    startRarityAudio(cinematic);

    return new Promise((resolve) => {
      let settled = false;
      let fallbackUsed = false;
      const timeout = window.setTimeout(() => complete(true), cinematic.duration + 1600);

      const cleanup = () => {
        window.clearTimeout(timeout);
        rarityVideo.removeEventListener('ended', onEnded);
        rarityVideo.removeEventListener('error', onError);
      };
      const complete = (completed) => {
        if (settled) return;
        settled = true;
        cleanup();
        waiting = null;
        advanceWaiting = null;
        resetRarityVideo();
        resolve(completed);
      };
      const start = async () => {
        try {
          await rarityVideo.play();
        } catch {
          onError();
        }
      };
      const onEnded = () => complete(true);
      const onError = () => {
        const fallback = rarityVideo.dataset.fallback;
        if (!fallbackUsed && fallback && !rarityVideo.src.endsWith(fallback)) {
          fallbackUsed = true;
          rarityVideo.src = fallback;
          rarityVideo.load();
          start();
          return;
        }
        complete(true);
      };

      waiting = () => complete(false);
      advanceWaiting = () => complete(true);
      rarityVideo.addEventListener('ended', onEnded);
      rarityVideo.addEventListener('error', onError);
      start();
    });
  }

  function finish() {
    waiting?.();
    clearParticles();
    resetRarityVideo(true);
    active = false;
    skipAllowed = false;
    packFastForwardRequested = false;
    advanceWaiting = null;
    root.classList.remove('show');
    root.dataset.phase = 'idle';
    root.dataset.outcome = '';
    delete root.dataset.enhanceTier;
    delete root.dataset.revealMode;
    root.setAttribute('aria-hidden', 'true');
    root.hidden = true;
    skipButton.hidden = true;
    revealAllButton.hidden = true;
  }

  function skip() {
    if (!active || !skipAllowed) return;
    if (root.dataset.mode === 'pack') {
      requestPackFastForward();
      return;
    }
    waiting?.();
    finish();
  }

  function requestPackFastForward() {
    if (!active || root.dataset.mode !== 'pack' || !skipAllowed || !canFastForwardPackPhase(root.dataset.phase)) return false;
    packFastForwardRequested = true;
    advanceWaiting?.();
    return true;
  }

  async function playEnhancement({ image, rarity, color, name, target, outcome, message }) {
    if (active) return false;
    active = true;
    unlockAudio();
    skipAllowed = false;
    root.hidden = false;
    root.dataset.mode = 'enhancement';
    root.dataset.outcome = outcome;
    root.dataset.enhanceTier = enhancementFxTier(target);
    root.dataset.phase = 'prepare';
    root.style.setProperty('--fx-rarity', color || '#d7ff35');
    root.setAttribute('aria-hidden', 'false');
    cardImage.src = image;
    cardImage.alt = name;
    rarityLabel.textContent = rarity;
    rarityLabel.dataset.rarity = rarity;
    frameImage.src = cardFramePath(rarity);
    cardName.textContent = name;
    const displayedLevel = outcome === 'success' ? target : Math.max(0, target - 1);
    levelLabel.dataset.starTier = enhancementTier(displayedLevel);
    levelLabel.dataset.starLevel = displayedLevel;
    levelLabel.setAttribute('aria-label', `${enhancementLabel(displayedLevel)} 강화`);
    levelLabel.title = `${enhancementLabel(displayedLevel)} 강화`;
    levelLabel.querySelector('b').textContent = `×${displayedLevel}`;
    levelLabel.querySelector('i').textContent = displayedLevel === 9 ? 'MAX' : '';
    levelBurst.querySelector('strong').textContent = `${enhancementLabel(displayedLevel)}`;
    verdict.textContent = message;
    skipButton.hidden = true;
    requestAnimationFrame(() => root.classList.add('show'));
    window.setTimeout(() => {
      if (!active) return;
      skipAllowed = true;
      skipButton.hidden = false;
    }, 350);

    for (const step of enhancementTimeline(outcome, reducedMotion.matches)) {
      if (!active) return false;
      root.dataset.phase = step.phase;
      if (step.phase === 'charge') playCue('enhance-charge');
      if (step.phase === 'impact') {
        const tierPower = { standard: 1, advanced: 1.08, elite: 1.16, max: 1.22 }[root.dataset.enhanceTier] ?? 1;
        burstParticles(outcome, outcome === 'success' ? 'celebration' : 'full', tierPower);
        playCue(`enhance-${outcome}`, rarity, tierPower);
      }
      const completed = await pause(step.duration);
      if (!completed) return false;
    }
    finish();
    return true;
  }

  function renderPackCards(cards, totalCount, { manual = false } = {}) {
    revealGrid.replaceChildren();
    revealGrid.style.setProperty('--fx-columns', Math.min(cards.length, 5));
    revealGrid.classList.toggle('bulk', cards.length > 5);
    cards.forEach((card, index) => {
      const item = document.createElement(manual ? 'button' : 'article');
      item.className = `fx-reveal-card${manual ? ' is-manual' : ''}`;
      if (manual) {
        item.type = 'button';
        item.setAttribute('aria-label', `${index + 1}번 카드 뒷면. 눌러서 공개`);
      }
      item.style.setProperty('--rarity', card.color);
      const inner = document.createElement('div');
      inner.className = 'fx-reveal-card-inner';
      const back = document.createElement('div');
      back.className = 'fx-reveal-card-back';
      const front = document.createElement('div');
      front.className = 'fx-reveal-card-front card-visual';
      const image = document.createElement('img');
      image.className = 'card-photo';
      image.src = card.image;
      image.alt = '';
      const frame = document.createElement('img');
      frame.className = 'card-frame-overlay';
      frame.src = cardFramePath(card.rarity);
      frame.alt = '';
      frame.setAttribute('aria-hidden', 'true');
      const rarity = document.createElement('b');
      rarity.className = 'card-rarity-mark';
      rarity.dataset.rarity = card.rarity;
      rarity.textContent = card.rarity;
      const name = document.createElement('strong');
      name.textContent = card.name;
      front.append(image, frame, rarity, name);
      inner.append(back, front);
      item.append(inner);
      revealGrid.append(item);
    });
    revealSummary.textContent = `고등급 카드 ${cards.length}장 · 전체 결과는 다음 화면`;
  }

  function revealPackCard(item, card, index, intensity = 'full', effects = true) {
    if (item.classList.contains('revealed')) return false;
    item.classList.add('revealed');
    item.setAttribute('aria-label', `${index + 1}번 카드 ${card.rarity} 등급 ${card.name} 공개됨`);
    if (effects) {
      playCue('card-flip', card.rarity);
      burstParticles('success', intensity);
    }
    return true;
  }

  function waitForManualPackReveal(cards, finalSummary) {
    root.dataset.phase = 'pack-reveal';
    delete root.dataset.revealComplete;
    const items = [...revealGrid.children];
    let revealedCount = 0;
    revealAllButton.hidden = items.length < 2;
    revealSummary.textContent = `카드를 눌러 공개 · ${revealedCount}/${items.length}`;

    return new Promise((resolve) => {
      let settled = false;
      const handlers = items.map((item, index) => {
        const handler = (event) => {
          event.stopPropagation();
          if (item.classList.contains('revealed')) {
            if (revealedCount === items.length) complete(true);
            return;
          }
          if (!active || !revealPackCard(item, cards[index], index, 'restrained')) return;
          revealedCount += 1;
          revealSummary.textContent = revealedCount === items.length
            ? finalSummary
            : `카드를 눌러 공개 · ${revealedCount}/${items.length}`;
          if (revealedCount === items.length) {
            root.dataset.revealComplete = 'true';
            revealAllButton.hidden = true;
            playCue('pack-summary');
          }
        };
        item.addEventListener('click', handler);
        return handler;
      });
      const revealAll = (event) => {
        event.stopPropagation();
        items.forEach((item, index) => revealPackCard(item, cards[index], index, 'restrained', false));
        revealedCount = items.length;
        revealSummary.textContent = finalSummary;
        root.dataset.revealComplete = 'true';
        revealAllButton.hidden = true;
        const highest = cards.reduce((best, card) => CINEMATIC_RARITIES.indexOf(card.rarity) > CINEMATIC_RARITIES.indexOf(best?.rarity) ? card : best, cards[0]);
        if (highest) playCue('card-flip', highest.rarity);
        burstParticles('success');
        playCue('pack-summary');
      };
      revealAllButton.addEventListener('click', revealAll);
      const complete = (completed) => {
        if (settled) return;
        settled = true;
        items.forEach((item, index) => item.removeEventListener('click', handlers[index]));
        revealAllButton.removeEventListener('click', revealAll);
        revealAllButton.hidden = true;
        delete root.dataset.revealComplete;
        waiting = null;
        advanceWaiting = null;
        resolve(completed);
      };
      waiting = () => complete(false);
      advanceWaiting = () => {
        if (revealedCount === items.length) complete(true);
      };
      if (items.length === 0) complete(true);
    });
  }

  async function playPackOpening({ image, name, cards, totalCount = cards.length }) {
    if (active) return false;
    active = true;
    unlockAudio();
    skipAllowed = false;
    packFastForwardRequested = false;
    const manualCards = selectManualPackRevealCards(cards);
    const timing = packOpeningTimeline(manualCards.length, reducedMotion.matches);
    const cinematic = selectRarityCinematic(cards, reducedMotion.matches);
    const manualReveal = manualCards.length > 0;
    root.hidden = false;
    root.dataset.mode = 'pack';
    root.dataset.outcome = '';
    root.dataset.phase = 'pack-prepare';
    root.style.setProperty('--fx-rarity', manualCards[0]?.color || '#d7ff35');
    root.setAttribute('aria-hidden', 'false');
    packImages.forEach((packImage) => {
      packImage.src = image;
      packImage.alt = '';
    });
    packName.textContent = name;
    root.dataset.revealMode = manualReveal ? 'manual' : 'auto';
    if (manualReveal) renderPackCards(manualCards, totalCount, { manual: true });
    else {
      revealGrid.replaceChildren();
      revealSummary.textContent = '';
    }
    prepareRarityVideo(cinematic);
    skipButton.hidden = true;
    requestAnimationFrame(() => root.classList.add('show'));
    window.setTimeout(() => {
      if (!active) return;
      skipAllowed = true;
    }, 350);

    for (const [phase, duration] of Object.entries(timing)) {
      if (!active) return false;
      if (packFastForwardRequested && phase !== 'reveal' && phase !== 'summary') continue;
      if (phase === 'reveal') {
        if (manualReveal) {
          const completed = await waitForManualPackReveal(manualCards, revealSummary.textContent);
          if (!completed) return false;
        }
        continue;
      }
      if (phase === 'summary') continue;
      root.dataset.phase = `pack-${phase}`;
      if (phase === 'approach') playCue('pack-approach');
      if (phase === 'charge') playCue('pack-charge');
      if (phase === 'burst') burstParticles('success');
      if (phase === 'burst') playCue('pack-burst');
      const completed = await pause(duration);
      if (!completed) return false;
      if (phase === 'burst' && cinematic && !packFastForwardRequested) {
        const videoCompleted = await playRarityVideo(cinematic);
        if (!videoCompleted) return false;
      }
    }
    finish();
    return true;
  }

  skipButton.addEventListener('click', skip);
  root.addEventListener('click', (event) => {
    if (event.button !== 0 || event.target.closest('[data-fx-reveal-all], [data-fx-skip]')) return;
    if (root.dataset.phase === 'pack-reveal') {
      if (root.dataset.revealComplete === 'true') advanceWaiting?.();
      return;
    }
    if (event.target.closest('[data-fx-reveal-grid]')) return;
    requestPackFastForward();
  });
  window.addEventListener('resize', () => { if (active) resizeCanvas(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden && active) finish(); });

  return {
    playEnhancement,
    playPackOpening,
    unlockAudio,
    setSoundEnabled,
    playUiCue: () => playCue('toggle'),
    skip,
    cancel: finish,
    get active() { return active; },
  };
}
