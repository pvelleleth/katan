/**
 * Lightweight procedural SFX for Settler using the Web Audio API.
 * No external audio assets required.
 */

export type SoundId =
	| 'ui'
	| 'gameStart'
	| 'dice'
	| 'dice7'
	| 'resources'
	| 'settlement'
	| 'road'
	| 'city'
	| 'devCard'
	| 'knight'
	| 'magic'
	| 'tradeOffer'
	| 'tradeAccept'
	| 'tradeReject'
	| 'tradeComplete'
	| 'discard'
	| 'steal'
	| 'robber'
	| 'turnEnd'
	| 'timerTick'
	| 'timerBuzz'
	| 'chat'
	| 'victory'
	| 'error';

const STORAGE_KEY = 'settler-sfx-muted';

type Tone = {
	freq: number;
	type?: OscillatorType;
	duration?: number;
	delay?: number;
	gain?: number;
	attack?: number;
	decay?: number;
	detune?: number;
};

let audioCtx: AudioContext | null = null;
let muted = false;
let unlocked = false;
let storageLoaded = false;

function loadMutedPreference() {
	if (storageLoaded || typeof localStorage === 'undefined') return;
	storageLoaded = true;
	try {
		muted = localStorage.getItem(STORAGE_KEY) === '1';
	} catch {
		// ignore storage errors
	}
}

function persistMutedPreference() {
	if (typeof localStorage === 'undefined') return;
	try {
		localStorage.setItem(STORAGE_KEY, muted ? '1' : '0');
	} catch {
		// ignore storage errors
	}
}

function getCtx(): AudioContext | null {
	if (typeof window === 'undefined') return null;

	const AudioContextCtor =
		window.AudioContext ||
		(window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;

	if (!AudioContextCtor) return null;

	if (!audioCtx) {
		audioCtx = new AudioContextCtor();
	}

	return audioCtx;
}

/** Call from a user gesture so browsers allow playback. */
export function unlockAudio() {
	const ctx = getCtx();
	if (!ctx) return;

	if (ctx.state === 'suspended') {
		void ctx.resume();
	}

	if (!unlocked) {
		// Silent blip primes the output graph on some browsers.
		const osc = ctx.createOscillator();
		const gain = ctx.createGain();
		gain.gain.value = 0.0001;
		osc.connect(gain);
		gain.connect(ctx.destination);
		osc.start();
		osc.stop(ctx.currentTime + 0.01);
		unlocked = true;
	}
}

export function isMuted() {
	loadMutedPreference();
	return muted;
}

export function setMuted(next: boolean) {
	loadMutedPreference();
	muted = next;
	persistMutedPreference();
}

export function toggleMuted() {
	setMuted(!isMuted());
	return muted;
}

function playTone(ctx: AudioContext, tone: Tone) {
	const now = ctx.currentTime + (tone.delay ?? 0);
	const duration = tone.duration ?? 0.12;
	const attack = tone.attack ?? 0.008;
	const decay = tone.decay ?? duration;
	const peak = tone.gain ?? 0.12;

	const osc = ctx.createOscillator();
	const gain = ctx.createGain();

	osc.type = tone.type ?? 'triangle';
	osc.frequency.setValueAtTime(tone.freq, now);
	if (tone.detune) {
		osc.detune.setValueAtTime(tone.detune, now);
	}

	gain.gain.setValueAtTime(0.0001, now);
	gain.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0001), now + attack);
	gain.gain.exponentialRampToValueAtTime(0.0001, now + Math.max(attack + 0.01, decay));

	osc.connect(gain);
	gain.connect(ctx.destination);
	osc.start(now);
	osc.stop(now + decay + 0.02);
}

function playNoise(
	ctx: AudioContext,
	opts: { duration?: number; delay?: number; gain?: number; filterFreq?: number } = {}
) {
	const duration = opts.duration ?? 0.08;
	const delay = opts.delay ?? 0;
	const peak = opts.gain ?? 0.08;
	const now = ctx.currentTime + delay;
	const sampleCount = Math.max(1, Math.floor(ctx.sampleRate * duration));
	const buffer = ctx.createBuffer(1, sampleCount, ctx.sampleRate);
	const data = buffer.getChannelData(0);

	for (let i = 0; i < sampleCount; i++) {
		// Soften the noise envelope in the sample itself.
		const t = i / sampleCount;
		data[i] = (Math.random() * 2 - 1) * (1 - t);
	}

	const source = ctx.createBufferSource();
	source.buffer = buffer;

	const filter = ctx.createBiquadFilter();
	filter.type = 'bandpass';
	filter.frequency.value = opts.filterFreq ?? 1800;
	filter.Q.value = 0.8;

	const gain = ctx.createGain();
	gain.gain.setValueAtTime(0.0001, now);
	gain.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0001), now + 0.005);
	gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);

	source.connect(filter);
	filter.connect(gain);
	gain.connect(ctx.destination);
	source.start(now);
	source.stop(now + duration + 0.02);
}

const recipes: Record<SoundId, (ctx: AudioContext) => void> = {
	ui: (ctx) => {
		playTone(ctx, { freq: 660, type: 'sine', duration: 0.05, gain: 0.05 });
	},
	gameStart: (ctx) => {
		playTone(ctx, { freq: 392, type: 'triangle', duration: 0.18, gain: 0.1 });
		playTone(ctx, { freq: 523.25, type: 'triangle', duration: 0.18, delay: 0.1, gain: 0.1 });
		playTone(ctx, { freq: 659.25, type: 'triangle', duration: 0.28, delay: 0.2, gain: 0.12 });
		playTone(ctx, { freq: 783.99, type: 'sine', duration: 0.35, delay: 0.32, gain: 0.08 });
	},
	dice: (ctx) => {
		playNoise(ctx, { duration: 0.07, gain: 0.1, filterFreq: 2400 });
		playNoise(ctx, { duration: 0.06, delay: 0.05, gain: 0.08, filterFreq: 1800 });
		playTone(ctx, { freq: 180, type: 'square', duration: 0.04, delay: 0.02, gain: 0.03 });
		playTone(ctx, { freq: 140, type: 'square', duration: 0.04, delay: 0.07, gain: 0.025 });
	},
	dice7: (ctx) => {
		playNoise(ctx, { duration: 0.1, gain: 0.1, filterFreq: 900 });
		playTone(ctx, { freq: 110, type: 'sawtooth', duration: 0.22, gain: 0.07 });
		playTone(ctx, { freq: 82, type: 'triangle', duration: 0.28, delay: 0.04, gain: 0.08 });
	},
	resources: (ctx) => {
		playTone(ctx, { freq: 523.25, type: 'sine', duration: 0.08, gain: 0.06 });
		playTone(ctx, { freq: 659.25, type: 'sine', duration: 0.1, delay: 0.05, gain: 0.06 });
		playTone(ctx, { freq: 783.99, type: 'sine', duration: 0.12, delay: 0.1, gain: 0.05 });
	},
	settlement: (ctx) => {
		playTone(ctx, { freq: 180, type: 'triangle', duration: 0.12, gain: 0.12 });
		playTone(ctx, { freq: 240, type: 'sine', duration: 0.1, delay: 0.04, gain: 0.07 });
		playNoise(ctx, { duration: 0.05, delay: 0.01, gain: 0.04, filterFreq: 600 });
	},
	road: (ctx) => {
		playNoise(ctx, { duration: 0.06, gain: 0.05, filterFreq: 700 });
		playTone(ctx, { freq: 220, type: 'triangle', duration: 0.08, gain: 0.06 });
	},
	city: (ctx) => {
		playTone(ctx, { freq: 196, type: 'triangle', duration: 0.14, gain: 0.12 });
		playTone(ctx, { freq: 294, type: 'triangle', duration: 0.16, delay: 0.06, gain: 0.1 });
		playTone(ctx, { freq: 392, type: 'sine', duration: 0.2, delay: 0.12, gain: 0.08 });
	},
	devCard: (ctx) => {
		playNoise(ctx, { duration: 0.05, gain: 0.05, filterFreq: 3200 });
		playTone(ctx, { freq: 740, type: 'sine', duration: 0.08, delay: 0.02, gain: 0.06 });
		playTone(ctx, { freq: 990, type: 'sine', duration: 0.1, delay: 0.07, gain: 0.05 });
	},
	knight: (ctx) => {
		playTone(ctx, { freq: 160, type: 'sawtooth', duration: 0.14, gain: 0.05 });
		playTone(ctx, { freq: 120, type: 'triangle', duration: 0.18, delay: 0.05, gain: 0.08 });
		playNoise(ctx, { duration: 0.08, delay: 0.02, gain: 0.05, filterFreq: 500 });
	},
	magic: (ctx) => {
		playTone(ctx, { freq: 523.25, type: 'sine', duration: 0.12, gain: 0.07 });
		playTone(ctx, { freq: 659.25, type: 'sine', duration: 0.12, delay: 0.08, gain: 0.07 });
		playTone(ctx, { freq: 880, type: 'sine', duration: 0.18, delay: 0.16, gain: 0.08 });
		playTone(ctx, { freq: 1174.66, type: 'triangle', duration: 0.2, delay: 0.24, gain: 0.05 });
	},
	tradeOffer: (ctx) => {
		playTone(ctx, { freq: 494, type: 'sine', duration: 0.07, gain: 0.06 });
		playTone(ctx, { freq: 622, type: 'sine', duration: 0.09, delay: 0.06, gain: 0.05 });
	},
	tradeAccept: (ctx) => {
		playTone(ctx, { freq: 523.25, type: 'triangle', duration: 0.08, gain: 0.07 });
		playTone(ctx, { freq: 698.46, type: 'triangle', duration: 0.12, delay: 0.07, gain: 0.07 });
	},
	tradeReject: (ctx) => {
		playTone(ctx, { freq: 330, type: 'triangle', duration: 0.08, gain: 0.05 });
		playTone(ctx, { freq: 247, type: 'triangle', duration: 0.1, delay: 0.06, gain: 0.05 });
	},
	tradeComplete: (ctx) => {
		playTone(ctx, { freq: 880, type: 'sine', duration: 0.05, gain: 0.05 });
		playTone(ctx, { freq: 1174.66, type: 'sine', duration: 0.06, delay: 0.04, gain: 0.05 });
		playTone(ctx, { freq: 1318.51, type: 'triangle', duration: 0.1, delay: 0.09, gain: 0.06 });
	},
	discard: (ctx) => {
		playNoise(ctx, { duration: 0.08, gain: 0.05, filterFreq: 1400 });
		playTone(ctx, { freq: 200, type: 'triangle', duration: 0.1, gain: 0.04 });
	},
	steal: (ctx) => {
		playTone(ctx, { freq: 420, type: 'sine', duration: 0.06, gain: 0.05 });
		playTone(ctx, { freq: 280, type: 'triangle', duration: 0.1, delay: 0.05, gain: 0.06 });
	},
	robber: (ctx) => {
		playTone(ctx, { freq: 90, type: 'sawtooth', duration: 0.22, gain: 0.05 });
		playTone(ctx, { freq: 70, type: 'triangle', duration: 0.28, delay: 0.04, gain: 0.07 });
		playNoise(ctx, { duration: 0.12, delay: 0.02, gain: 0.06, filterFreq: 400 });
	},
	turnEnd: (ctx) => {
		playTone(ctx, { freq: 392, type: 'sine', duration: 0.07, gain: 0.04 });
		playTone(ctx, { freq: 294, type: 'sine', duration: 0.1, delay: 0.06, gain: 0.04 });
	},
	timerTick: (ctx) => {
		// Sharp clock tick — short high click + soft low body.
		playTone(ctx, { freq: 1400, type: 'square', duration: 0.035, gain: 0.04, attack: 0.002 });
		playTone(ctx, { freq: 900, type: 'triangle', duration: 0.05, gain: 0.035, attack: 0.002 });
	},
	timerBuzz: (ctx) => {
		// Harsh timeout buzzer.
		playTone(ctx, { freq: 160, type: 'sawtooth', duration: 0.28, gain: 0.07, attack: 0.01 });
		playTone(ctx, { freq: 140, type: 'square', duration: 0.28, gain: 0.045, attack: 0.01 });
		playTone(ctx, {
			freq: 180,
			type: 'sawtooth',
			duration: 0.22,
			delay: 0.18,
			gain: 0.06,
			attack: 0.01
		});
		playNoise(ctx, { duration: 0.2, gain: 0.04, filterFreq: 500 });
	},
	chat: (ctx) => {
		playTone(ctx, { freq: 820, type: 'sine', duration: 0.04, gain: 0.035 });
	},
	victory: (ctx) => {
		const notes = [523.25, 659.25, 783.99, 1046.5];
		notes.forEach((freq, i) => {
			playTone(ctx, {
				freq,
				type: i === notes.length - 1 ? 'triangle' : 'sine',
				duration: 0.22 + i * 0.04,
				delay: i * 0.12,
				gain: 0.09
			});
		});
	},
	error: (ctx) => {
		playTone(ctx, { freq: 180, type: 'square', duration: 0.1, gain: 0.04 });
		playTone(ctx, { freq: 140, type: 'square', duration: 0.14, delay: 0.08, gain: 0.04 });
	}
};

export function playSound(id: SoundId) {
	loadMutedPreference();
	if (muted) return;

	const ctx = getCtx();
	if (!ctx) return;

	if (ctx.state === 'suspended') {
		void ctx.resume().then(() => {
			recipes[id]?.(ctx);
		});
		return;
	}

	recipes[id]?.(ctx);
}

/**
 * Urgency tick for the last few seconds of the turn timer.
 * `remainingSeconds` 5→1 raises pitch/volume slightly as time runs out.
 */
export function playTimerTick(remainingSeconds: number) {
	loadMutedPreference();
	if (muted) return;

	const ctx = getCtx();
	if (!ctx) return;

	const play = () => {
		// remainingSeconds: 5 softest/lowest → 1 sharpest/highest
		const urgency = Math.max(0, Math.min(4, 5 - remainingSeconds));
		const freq = 1100 + urgency * 120;
		const gain = 0.035 + urgency * 0.012;

		playTone(ctx, {
			freq,
			type: 'square',
			duration: 0.035,
			gain,
			attack: 0.002
		});
		playTone(ctx, {
			freq: freq * 0.65,
			type: 'triangle',
			duration: 0.05,
			gain: gain * 0.85,
			attack: 0.002
		});
	};

	if (ctx.state === 'suspended') {
		void ctx.resume().then(play);
		return;
	}

	play();
}

/**
 * Map a server game_log event_type (+ optional payload/message) to SFX.
 * Returns false when no sound is mapped.
 */
export function playGameEvent(
	eventType: string,
	payload?: Record<string, unknown> | null,
	message?: string | null
) {
	switch (eventType) {
		case 'game_started':
			playSound('gameStart');
			return true;
		case 'dice_rolled': {
			const total = Number(payload?.total ?? 0);
			if (total === 7) {
				playSound('dice7');
			} else {
				playSound('dice');
				// Payload does not always include granted resources; the log line does.
				const granted =
					(payload?.resources_granted as Record<string, unknown> | undefined) ?? null;
				const someoneGotResources =
					(granted && Object.keys(granted).length > 0) ||
					(typeof message === 'string' && /\bgot\b/i.test(message));
				if (someoneGotResources) {
					window.setTimeout(() => playSound('resources'), 140);
				}
			}
			return true;
		}
		case 'settlement_placed':
			playSound('settlement');
			return true;
		case 'road_placed':
		case 'road_building_played':
			playSound('road');
			return true;
		case 'city_placed':
			playSound('city');
			return true;
		case 'development_card_purchased':
			playSound('devCard');
			return true;
		case 'knight_played':
			playSound('knight');
			return true;
		case 'monopoly_played':
		case 'year_of_plenty_played':
			playSound('magic');
			return true;
		case 'player_trade_proposed':
			playSound('tradeOffer');
			return true;
		case 'player_trade_accepted':
			playSound('tradeAccept');
			return true;
		case 'player_trade_rejected':
		case 'player_trade_cancelled':
			playSound('tradeReject');
			return true;
		case 'player_trade_completed':
		case 'bank_trade_completed':
			playSound('tradeComplete');
			return true;
		case 'robber_discarded':
			playSound('discard');
			return true;
		case 'robber_moved':
			playSound('robber');
			return true;
		case 'robber_stolen':
			playSound('steal');
			return true;
		case 'turn_ended':
		case 'turn_timeout':
			playSound('turnEnd');
			return true;
		case 'chat_message':
			playSound('chat');
			return true;
		default:
			return false;
	}
}

/** Attach one-time unlock handlers so SFX work after first interaction. */
export function installAudioUnlock() {
	if (typeof window === 'undefined') return () => {};

	const unlock = () => {
		unlockAudio();
	};

	const events: Array<keyof WindowEventMap> = ['pointerdown', 'keydown', 'touchstart'];
	events.forEach((eventName) => {
		window.addEventListener(eventName, unlock, { once: true, passive: true });
	});

	return () => {
		events.forEach((eventName) => {
			window.removeEventListener(eventName, unlock);
		});
	};
}
