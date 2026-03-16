<script lang="ts">
	import { getLegalRoadBuildingEdges } from './devCards';

	export let board: any;
	export let gameState: any;
	export let playerId: string;
	export let players: any[];
	export let sendGameAction: (action: string, payload?: any) => void;
	export let pendingBoardDevCardAction: 'knight' | 'road_building' | null = null;
	export let roadBuildingSelection: string[] = [];
	export let onKnightTileSelect: (tileId: string) => void;
	export let onRoadBuildingEdgeSelect: (edgeId: string) => void;

	// Hexagon dimensions
	const HEX_SIZE = 60;
	const HEX_WIDTH = Math.sqrt(3) * HEX_SIZE;
	const HEX_HEIGHT = 2 * HEX_SIZE;

	// Calculate viewbox based on board tiles
	$: minX = Math.min(...board.tiles.map((t: any) => t.x));
	$: maxX = Math.max(...board.tiles.map((t: any) => t.x));
	$: minY = Math.min(...board.tiles.map((t: any) => t.y));
	$: maxY = Math.max(...board.tiles.map((t: any) => t.y));

	// Convert backend coordinates to pixel coordinates
	function getPixelCoords(bx: number, by: number) {
		const x = bx * ((HEX_SIZE * Math.sqrt(3)) / 2);
		const y = by * (HEX_SIZE / 2);
		return { x, y };
	}

	const resourceColors: Record<string, string> = {
		Wood: '#2E7D32', // Forest green
		Brick: '#C62828', // Firebrick
		Sheep: '#8BC34A', // Light green
		Wheat: '#FBC02D', // Goldenrod
		Ore: '#546E7A', // Slate gray
		Desert: '#D4A373' // Tan
	};

	function getPips(token: number) {
		if (!token) return 0;
		const pips = 6 - Math.abs(7 - token);
		return pips > 0 ? pips : 0;
	}

	function getHexPoints(centerX: number, centerY: number, size: number) {
		const points = [];
		for (let i = 0; i < 6; i++) {
			const angle_deg = 60 * i - 30;
			const angle_rad = (Math.PI / 180) * angle_deg;
			points.push(
				`${centerX + size * Math.cos(angle_rad)},${centerY + size * Math.sin(angle_rad)}`
			);
		}
		return points.join(' ');
	}

	function getVertexCoords(vertexId: string) {
		const vertex = board.vertices.find((v: any) => v.id === vertexId);
		if (!vertex) return { x: 0, y: 0 };
		return getPixelCoords(vertex.x, vertex.y);
	}

	const harborColors: Record<string, string> = {
		ThreeToOne: '#ffffff',
		WoodTwoToOne: '#2E7D32',
		BrickTwoToOne: '#C62828',
		SheepTwoToOne: '#8BC34A',
		WheatTwoToOne: '#FBC02D',
		OreTwoToOne: '#546E7A'
	};

	const harborLabels: Record<string, string> = {
		ThreeToOne: '3:1',
		WoodTwoToOne: 'Wood',
		BrickTwoToOne: 'Brick',
		SheepTwoToOne: 'Sheep',
		WheatTwoToOne: 'Wheat',
		OreTwoToOne: 'Ore'
	};

	$: isMyTurn = gameState.turn.current_player_id === playerId;
	$: phase = gameState.turn.phase;
	$: myPlayer = players.find((player) => player.id === playerId);
	$: canPlaceSettlement =
		isMyTurn && (phase === 'Setup1Settlement' || phase === 'Setup2Settlement' || phase === 'Main');
	$: canPlaceRoad =
		isMyTurn &&
		(phase === 'Setup1Road' ||
			phase === 'Setup2Road' ||
			phase === 'Main' ||
			pendingBoardDevCardAction === 'road_building');
	$: canMoveRobber = isMyTurn && (phase === 'MoveRobber' || pendingBoardDevCardAction === 'knight');
	$: showNormalRoadTargets = canPlaceRoad && pendingBoardDevCardAction !== 'road_building';
	$: legalRoadBuildingEdgeIds = new Set(
		getLegalRoadBuildingEdges(
			pendingBoardDevCardAction === 'road_building' ? board : null,
			playerId,
			roadBuildingSelection,
			myPlayer?.roads_left ?? 0
		).map((edge) => edge.id)
	);

	function getPlayerColor(pId: string) {
		const p = players.find((p) => p.id === pId);
		if (!p) return '#ffffff';
		const colors: Record<string, string> = {
			brick: '#B22222',
			ocean: '#146c8e',
			wheat: '#DAA520',
			forest: '#2E8B57',
			wood: '#8B4513'
		};
		return colors[p.color] || '#ffffff';
	}

	function handleVertexClick(vertexId: string) {
		if (!canPlaceSettlement) return;
		// For setup phase, free is true. For main phase, free is false.
		const isSetup = phase.startsWith('Setup');
		sendGameAction('place_settlement', { vertex_id: vertexId, free: isSetup });
	}

	function handleEdgeClick(edgeId: string) {
		if (pendingBoardDevCardAction === 'road_building') {
			if (!legalRoadBuildingEdgeIds.has(edgeId)) return;
			onRoadBuildingEdgeSelect(edgeId);
			return;
		}

		if (!canPlaceRoad) return;
		const isSetup = phase.startsWith('Setup');
		sendGameAction('place_road', { edge_id: edgeId, free: isSetup });
	}

	function handleTileClick(tileId: string) {
		if (!canMoveRobber) return;
		// Can't move robber to the tile it's already on
		const currentRobberTile = board.tiles.find((t: any) => t.has_robber);
		if (currentRobberTile && currentRobberTile.id === tileId) return;

		if (pendingBoardDevCardAction === 'knight') {
			onKnightTileSelect(tileId);
			return;
		}

		sendGameAction('move_robber', { tile_id: tileId });
	}
</script>

<div class="flex h-full w-full items-center justify-center">
	<svg
		width="100%"
		height="100%"
		viewBox="-300 -300 600 600"
		preserveAspectRatio="xMidYMid meet"
		class="drop-shadow-xl"
	>
		<defs>
			<!-- Ocean Background Gradient -->
			<radialGradient id="ocean-bg" cx="50%" cy="50%" r="70%">
				<stop offset="0%" stop-color="#4facfe" />
				<stop offset="100%" stop-color="#00f2fe" />
			</radialGradient>

			<!-- Hexagon Clip Path -->
			<clipPath id="hex-clip">
				<polygon points={getHexPoints(0, 0, HEX_SIZE - 2)} />
			</clipPath>

			<!-- Tile Gradients to make them look 3D/textured without images -->
			<radialGradient id="grad-Wood" cx="30%" cy="30%" r="70%">
				<stop offset="0%" stop-color="#4CAF50" />
				<stop offset="100%" stop-color="#1B5E20" />
			</radialGradient>
			<radialGradient id="grad-Brick" cx="30%" cy="30%" r="70%">
				<stop offset="0%" stop-color="#E53935" />
				<stop offset="100%" stop-color="#B71C1C" />
			</radialGradient>
			<radialGradient id="grad-Sheep" cx="30%" cy="30%" r="70%">
				<stop offset="0%" stop-color="#AED581" />
				<stop offset="100%" stop-color="#689F38" />
			</radialGradient>
			<radialGradient id="grad-Wheat" cx="30%" cy="30%" r="70%">
				<stop offset="0%" stop-color="#FFF176" />
				<stop offset="100%" stop-color="#F57F17" />
			</radialGradient>
			<radialGradient id="grad-Ore" cx="30%" cy="30%" r="70%">
				<stop offset="0%" stop-color="#90A4AE" />
				<stop offset="100%" stop-color="#37474F" />
			</radialGradient>
			<radialGradient id="grad-Desert" cx="30%" cy="30%" r="70%">
				<stop offset="0%" stop-color="#FFE082" />
				<stop offset="100%" stop-color="#FFB300" />
			</radialGradient>

			<!-- Inner shadow filter for tiles -->
			<filter id="inner-shadow">
				<feOffset dx="0" dy="0" />
				<feGaussianBlur stdDeviation="3" result="offset-blur" />
				<feComposite operator="out" in="SourceGraphic" in2="offset-blur" result="inverse" />
				<feFlood flood-color="black" flood-opacity="0.4" result="color" />
				<feComposite operator="in" in="color" in2="inverse" result="shadow" />
				<feComposite operator="over" in="shadow" in2="SourceGraphic" />
			</filter>
		</defs>

		<!-- Ocean Background -->
		<rect x="-2000" y="-2000" width="4000" height="4000" fill="url(#ocean-bg)" />

		<!-- Tiles -->
		<g class="tiles">
			{#each board.tiles as tile}
				{@const { x, y } = getPixelCoords(tile.x, tile.y)}
				<!-- svelte-ignore a11y_click_events_have_key_events -->
				<!-- svelte-ignore a11y_no_static_element_interactions -->
				<g
					transform="translate({x}, {y})"
					class:cursor-pointer={canMoveRobber && !tile.has_robber}
					on:click={() => handleTileClick(tile.id)}
				>
					<!-- Base tile with gradient -->
					<polygon
						points={getHexPoints(0, 0, HEX_SIZE - 1)}
						fill="url(#grad-{tile.resource})"
						stroke="#3e2723"
						stroke-width="3"
						stroke-linejoin="round"
						class="transition-transform {canMoveRobber && !tile.has_robber
							? 'hover:scale-[1.05] hover:stroke-white'
							: 'hover:scale-[1.02]'}"
					/>

					<!-- Inner highlight/shadow for 3D effect -->
					<polygon
						points={getHexPoints(0, 0, HEX_SIZE - 3)}
						fill="none"
						stroke="#ffffff"
						stroke-width="1.5"
						stroke-opacity="0.2"
					/>

					<!-- Resource Icon/Pattern (Drawn with SVG) -->
					<g clip-path="url(#hex-clip)">
						{#if tile.resource === 'Wood'}
							<g transform="scale(1.4)">
								<!-- Dense forest pattern -->
								{#each [[-15, -10], [15, -15], [0, -20], [-20, 5], [20, 0], [-10, 15], [10, 10], [0, 0], [-5, -8], [8, -2]] as [tx, ty]}
									<g transform="translate({tx}, {ty}) scale(1.1)">
										<path
											d="M0,-12 L6,0 L2,0 L8,10 L-8,10 L-2,0 L-6,0 Z"
											fill="#1B5E20"
											opacity="0.9"
										/>
										<path d="M0,-12 L0,10 L-8,10 L-2,0 L-6,0 Z" fill="#2E7D32" opacity="1" />
										<rect x="-1.5" y="10" width="3" height="4" fill="#4E342E" />
									</g>
								{/each}
							</g>
						{:else if tile.resource === 'Brick'}
							<g transform="scale(1.4)">
								<!-- Clay pit / Brick stacks -->
								<ellipse cx="0" cy="5" rx="25" ry="12" fill="#880E4F" opacity="0.4" />
								<ellipse cx="-5" cy="8" rx="15" ry="6" fill="#4A148C" opacity="0.3" />

								{#each [[-15, -5], [0, -12], [12, 2], [-5, 10], [18, -8]] as [tx, ty]}
									<g transform="translate({tx}, {ty}) scale(1.1)">
										<!-- Stack of bricks -->
										<rect
											x="-8"
											y="0"
											width="16"
											height="6"
											fill="#C62828"
											stroke="#880E4F"
											stroke-width="0.5"
										/>
										<rect
											x="-8"
											y="-6"
											width="7"
											height="6"
											fill="#D32F2F"
											stroke="#880E4F"
											stroke-width="0.5"
										/>
										<rect
											x="0"
											y="-6"
											width="8"
											height="6"
											fill="#D32F2F"
											stroke="#880E4F"
											stroke-width="0.5"
										/>
										<rect
											x="-4"
											y="-12"
											width="8"
											height="6"
											fill="#E53935"
											stroke="#880E4F"
											stroke-width="0.5"
										/>
									</g>
								{/each}
							</g>
						{:else if tile.resource === 'Sheep'}
							<g transform="scale(1.4)">
								<!-- Rolling hills -->
								<path
									d="M-30,5 Q-15,-10 0,0 T30,-5 L30,20 L-30,20 Z"
									fill="#8BC34A"
									opacity="0.5"
								/>
								<path
									d="M-30,15 Q-10,5 10,15 T30,10 L30,30 L-30,30 Z"
									fill="#7CB342"
									opacity="0.6"
								/>

								<!-- Flocks of sheep -->
								{#each [[-15, -5], [12, -12], [0, 5], [-20, 12], [18, 8], [-5, -15], [22, -2]] as [tx, ty]}
									<g transform="translate({tx}, {ty}) scale(1.2)">
										<!-- Legs -->
										<line x1="-3" y1="4" x2="-3" y2="7" stroke="#212121" stroke-width="1.5" />
										<line x1="3" y1="4" x2="3" y2="7" stroke="#212121" stroke-width="1.5" />
										<!-- Wooly body -->
										<circle cx="-3" cy="0" r="3.5" fill="#FAFAFA" />
										<circle cx="3" cy="0" r="3.5" fill="#FAFAFA" />
										<circle cx="0" cy="-3" r="4" fill="#FAFAFA" />
										<circle cx="0" cy="2" r="3.5" fill="#FAFAFA" />
										<!-- Head -->
										<ellipse cx="-5" cy="-1" rx="2.5" ry="2" fill="#212121" />
									</g>
								{/each}
							</g>
						{:else if tile.resource === 'Wheat'}
							<g transform="scale(1.4)">
								<!-- Field rows -->
								<path
									d="M-25,-15 L25,15 M-15,-25 L35,5 M-35,-5 L15,25"
									stroke="#F9A825"
									stroke-width="4"
									opacity="0.4"
								/>

								<!-- Wheat stalks -->
								{#each [[-15, -10], [0, -15], [15, -5], [-10, 5], [10, 12], [-5, 15], [-20, 8], [20, -15], [0, 0], [-25, -5], [25, 5]] as [tx, ty]}
									<g transform="translate({tx}, {ty}) scale(1.2)">
										<!-- Stem -->
										<path d="M0,8 Q2,0 0,-8" fill="none" stroke="#F57F17" stroke-width="1.5" />
										<!-- Grains -->
										<path d="M0,-8 Q-3,-5 0,-2 Q3,-5 0,-8" fill="#FFF176" />
										<path
											d="M-1,-5 Q-4,-2 -1,1 Q2,-2 -1,-5"
											fill="#FFF176"
											transform="rotate(-20)"
										/>
										<path d="M1,-5 Q4,-2 1,1 Q-2,-2 1,-5" fill="#FFF176" transform="rotate(20)" />
									</g>
								{/each}
							</g>
						{:else if tile.resource === 'Ore'}
							<g transform="scale(1.5)">
								<!-- Mountain range -->
								<path
									d="M-30,15 L-15,-10 L-5,5 L10,-20 L25,10 Z"
									fill="#455A64"
									stroke="#263238"
									stroke-width="1"
								/>
								<!-- Snow caps -->
								<path d="M-15,-10 L-11,-3 L-15,0 L-18,-4 Z" fill="#CFD8DC" />
								<path d="M10,-20 L15,-10 L10,-7 L5,-12 Z" fill="#CFD8DC" />

								<!-- Ore rocks in foreground -->
								<path d="M-10,15 L-5,8 L5,12 L0,20 Z" fill="#263238" />
								<path d="M5,12 L12,5 L18,15 L10,22 Z" fill="#37474F" />
								<path d="M-20,10 L-15,5 L-10,12 Z" fill="#37474F" />
								<path d="M15,5 L20,0 L25,8 Z" fill="#263238" />
							</g>
						{:else if tile.resource === 'Desert'}
							<g transform="scale(1.4)">
								<!-- Sand dunes -->
								<path
									d="M-35,5 Q-15,-10 5,0 T40,-5"
									fill="none"
									stroke="#FF8F00"
									stroke-width="3"
									opacity="0.4"
								/>
								<path
									d="M-25,15 Q-5,0 15,10 T35,5"
									fill="none"
									stroke="#FF8F00"
									stroke-width="2.5"
									opacity="0.3"
								/>
								<path
									d="M-30,-5 Q-10,-15 10,-5 T35,-10"
									fill="none"
									stroke="#FF8F00"
									stroke-width="2"
									opacity="0.2"
								/>

								<!-- Cactus -->
								<g transform="translate(-15, -5) scale(1.1)">
									<rect x="-1.5" y="-10" width="3" height="15" rx="1.5" fill="#2E7D32" />
									<path
										d="M-1.5,-2 Q-6,-2 -6,-6 L-6,-8"
										fill="none"
										stroke="#2E7D32"
										stroke-width="2"
										stroke-linecap="round"
									/>
									<path
										d="M1.5,0 Q6,0 6,-4 L6,-6"
										fill="none"
										stroke="#2E7D32"
										stroke-width="2"
										stroke-linecap="round"
									/>
								</g>

								<!-- Animal skull -->
								<g transform="translate(15, 10) scale(0.9)" opacity="0.8">
									<path
										d="M-4,-2 C-4,-6 4,-6 4,-2 C4,2 2,6 0,6 C-2,6 -4,2 -4,-2 Z"
										fill="#FFF8E1"
									/>
									<circle cx="-1.5" cy="-1" r="1" fill="#FFB300" />
									<circle cx="1.5" cy="-1" r="1" fill="#FFB300" />
									<path
										d="M-3,-4 Q-8,-8 -6,-10"
										fill="none"
										stroke="#FFF8E1"
										stroke-width="1.5"
										stroke-linecap="round"
									/>
									<path
										d="M3,-4 Q8,-8 6,-10"
										fill="none"
										stroke="#FFF8E1"
										stroke-width="1.5"
										stroke-linecap="round"
									/>
								</g>
							</g>
						{/if}
					</g>

					<!-- Number Token -->
					{#if tile.token}
						{@const pips = getPips(tile.token)}
						<g transform="translate(0, 0)">
							<!-- Token Background -->
							<circle cx="0" cy="0" r="18" fill="#FFF8E1" stroke="#3E2723" stroke-width="1.5" />

							<!-- Number -->
							<text
								x="0"
								y="4"
								text-anchor="middle"
								font-size="16"
								font-weight="900"
								font-family="Georgia, serif"
								fill={tile.token === 6 || tile.token === 8 ? '#D32F2F' : '#212121'}
							>
								{tile.token}
							</text>

							<!-- Pips -->
							<g transform="translate(0, 12)">
								{#each Array(pips) as _, i}
									<circle
										cx={(i - (pips - 1) / 2) * 4}
										cy="0"
										r="1.5"
										fill={tile.token === 6 || tile.token === 8 ? '#D32F2F' : '#212121'}
									/>
								{/each}
							</g>
						</g>
					{/if}

					<!-- Robber -->
					{#if tile.has_robber}
						<g transform="translate(0, -15)">
							<!-- Shadow -->
							<ellipse cx="2" cy="12" rx="8" ry="4" fill="rgba(0,0,0,0.5)" />
							<!-- Body -->
							<path
								d="M -8 10 C -8 0, -4 -5, -2 -10 C -2 -15, 2 -15, 2 -10 C 4 -5, 8 0, 8 10 Z"
								fill="#212121"
							/>
							<path
								d="M -8 10 C -8 0, -4 -5, -2 -10 C -2 -15, 2 -15, 2 -10 C 4 -5, 8 0, 8 10 Z"
								fill="url(#grad-Ore)"
								opacity="0.3"
							/>
							<!-- Base -->
							<rect x="-10" y="10" width="20" height="4" rx="2" fill="#212121" />
						</g>
					{/if}
				</g>
			{/each}
		</g>

		<!-- Harbors -->
		<g class="harbors">
			{#if board.harbors}
				{#each board.harbors as harbor}
					{@const v1 = getVertexCoords(harbor.vertex_ids[0])}
					{@const v2 = getVertexCoords(harbor.vertex_ids[1])}
					{@const mx = (v1.x + v2.x) / 2}
					{@const my = (v1.y + v2.y) / 2}
					{@const len = Math.sqrt(mx * mx + my * my) || 1}
					{@const nx = mx / len}
					{@const ny = my / len}
					{@const push = 22}
					{@const hx = mx + nx * push}
					{@const hy = my + ny * push}

					{@const len1 = Math.sqrt((hx - v1.x) ** 2 + (hy - v1.y) ** 2) || 1}
					{@const len2 = Math.sqrt((hx - v2.x) ** 2 + (hy - v2.y) ** 2) || 1}
					<!-- Railway tracks sticking out -->
					<!-- Track 1 -->
					<g>
						<line
							x1={v1.x}
							y1={v1.y}
							x2={hx}
							y2={hy}
							stroke="#5D4037"
							stroke-width="3"
							stroke-linecap="round"
						/>
						<!-- Cross ties -->
						{#each [0.2, 0.4, 0.6, 0.8] as t}
							{@const cx = v1.x + (hx - v1.x) * t}
							{@const cy = v1.y + (hy - v1.y) * t}
							{@const perpX = (-(hy - v1.y) / len1) * 3}
							{@const perpY = ((hx - v1.x) / len1) * 3}
							<line
								x1={cx - perpX}
								y1={cy - perpY}
								x2={cx + perpX}
								y2={cy + perpY}
								stroke="#3E2723"
								stroke-width="1.5"
							/>
						{/each}
					</g>

					<!-- Track 2 -->
					<g>
						<line
							x1={v2.x}
							y1={v2.y}
							x2={hx}
							y2={hy}
							stroke="#5D4037"
							stroke-width="3"
							stroke-linecap="round"
						/>
						<!-- Cross ties -->
						{#each [0.2, 0.4, 0.6, 0.8] as t}
							{@const cx = v2.x + (hx - v2.x) * t}
							{@const cy = v2.y + (hy - v2.y) * t}
							{@const perpX = (-(hy - v2.y) / len2) * 3}
							{@const perpY = ((hx - v2.x) / len2) * 3}
							<line
								x1={cx - perpX}
								y1={cy - perpY}
								x2={cx + perpX}
								y2={cy + perpY}
								stroke="#3E2723"
								stroke-width="1.5"
							/>
						{/each}
					</g>

					<!-- Harbor Badge -->
					<g transform="translate({hx}, {hy})">
						<!-- Outer ring -->
						<circle cx="0" cy="0" r="16" fill="#FFF8E1" stroke="#3E2723" stroke-width="2" />
						<!-- Inner colored circle -->
						<circle cx="0" cy="0" r="13" fill={harborColors[harbor.kind] || '#fff'} />

						<!-- Icons -->
						{#if harbor.kind === 'ThreeToOne'}
							<text
								x="0"
								y="4"
								text-anchor="middle"
								font-size="11"
								font-weight="900"
								font-family="Arial, sans-serif"
								fill="#212121">3:1</text
							>
						{:else if harbor.kind === 'WoodTwoToOne'}
							<g transform="translate(0, 1) scale(0.6)">
								<path d="M0,-12 L6,0 L2,0 L8,10 L-8,10 L-2,0 L-6,0 Z" fill="#1B5E20" />
								<rect x="-1.5" y="10" width="3" height="4" fill="#4E342E" />
							</g>
						{:else if harbor.kind === 'BrickTwoToOne'}
							<g transform="translate(0, 0) scale(0.7)">
								<rect x="-6" y="-4" width="12" height="6" fill="#FFF" opacity="0.9" />
								<rect
									x="-6"
									y="-4"
									width="12"
									height="6"
									fill="#C62828"
									stroke="#880E4F"
									stroke-width="0.5"
								/>
								<rect
									x="-6"
									y="2"
									width="6"
									height="4"
									fill="#D32F2F"
									stroke="#880E4F"
									stroke-width="0.5"
								/>
								<rect
									x="0"
									y="2"
									width="6"
									height="4"
									fill="#D32F2F"
									stroke="#880E4F"
									stroke-width="0.5"
								/>
							</g>
						{:else if harbor.kind === 'SheepTwoToOne'}
							<g transform="translate(0, 2) scale(0.8)">
								<line x1="-3" y1="2" x2="-3" y2="5" stroke="#212121" stroke-width="1.5" />
								<line x1="3" y1="2" x2="3" y2="5" stroke="#212121" stroke-width="1.5" />
								<circle cx="-3" cy="-2" r="3.5" fill="#FAFAFA" />
								<circle cx="3" cy="-2" r="3.5" fill="#FAFAFA" />
								<circle cx="0" cy="-5" r="4" fill="#FAFAFA" />
								<circle cx="0" cy="0" r="3.5" fill="#FAFAFA" />
								<ellipse cx="-5" cy="-3" rx="2.5" ry="2" fill="#212121" />
							</g>
						{:else if harbor.kind === 'WheatTwoToOne'}
							<g transform="translate(0, 0) scale(0.8)">
								<path d="M0,8 Q2,0 0,-8" fill="none" stroke="#F57F17" stroke-width="1.5" />
								<path d="M0,-8 Q-3,-5 0,-2 Q3,-5 0,-8" fill="#FFF176" />
								<path d="M-1,-5 Q-4,-2 -1,1 Q2,-2 -1,-5" fill="#FFF176" transform="rotate(-20)" />
								<path d="M1,-5 Q4,-2 1,1 Q-2,-2 1,-5" fill="#FFF176" transform="rotate(20)" />
							</g>
						{:else if harbor.kind === 'OreTwoToOne'}
							<g transform="translate(0, 2) scale(0.6)">
								<path d="M-10,5 L-5,-5 L5,-1 L15,5 Z" fill="#263238" />
								<path d="M-5,-5 L0,-12 L10,-5 L5,2 Z" fill="#37474F" />
							</g>
						{/if}
					</g>
				{/each}
			{/if}
		</g>

		<!-- Edges (Roads) -->
		<g class="edges">
			{#each board.edges as edge}
				{@const v1 = getVertexCoords(edge.v1)}
				{@const v2 = getVertexCoords(edge.v2)}
				{@const isRoadBuildingSelected = roadBuildingSelection.includes(edge.id)}
				{@const isRoadBuildingCandidate =
					pendingBoardDevCardAction === 'road_building' && legalRoadBuildingEdgeIds.has(edge.id)}

				<!-- Interactive hit area for edges -->
				{#if ((showNormalRoadTargets && !edge.road) || isRoadBuildingCandidate) && !isRoadBuildingSelected}
					<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
					<line
						x1={v1.x}
						y1={v1.y}
						x2={v2.x}
						y2={v2.y}
						stroke="transparent"
						stroke-width="15"
						class="cursor-pointer transition-colors {isRoadBuildingCandidate
							? 'hover:stroke-wheat/70'
							: 'hover:stroke-white/50'}"
						on:click={() => handleEdgeClick(edge.id)}
					/>
				{/if}

				<!-- Actual road -->
				{#if edge.road}
					<line
						x1={v1.x}
						y1={v1.y}
						x2={v2.x}
						y2={v2.y}
						stroke={getPlayerColor(edge.road.player_id)}
						stroke-width="8"
						stroke-linecap="round"
						class="drop-shadow-md"
					/>
					<line
						x1={v1.x}
						y1={v1.y}
						x2={v2.x}
						y2={v2.y}
						stroke="#000000"
						stroke-width="2"
						stroke-opacity="0.3"
						stroke-linecap="round"
					/>
				{/if}

				{#if isRoadBuildingSelected}
					<line
						x1={v1.x}
						y1={v1.y}
						x2={v2.x}
						y2={v2.y}
						stroke="#FBC02D"
						stroke-width="10"
						stroke-linecap="round"
						stroke-dasharray="8 6"
						class="drop-shadow-md"
					/>
				{:else if isRoadBuildingCandidate}
					<line
						x1={v1.x}
						y1={v1.y}
						x2={v2.x}
						y2={v2.y}
						stroke="#FFF8E1"
						stroke-width="4"
						stroke-linecap="round"
						stroke-opacity="0.9"
					/>
				{/if}
			{/each}
		</g>

		<!-- Vertices (Settlements/Cities) -->
		<g class="vertices">
			{#each board.vertices as vertex}
				{@const { x, y } = getPixelCoords(vertex.x, vertex.y)}

				<!-- Interactive hit area for vertices -->
				{#if canPlaceSettlement && !vertex.building}
					<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
					<circle
						cx={x}
						cy={y}
						r="12"
						fill="transparent"
						class="cursor-pointer transition-colors hover:fill-white/50"
						on:click={() => handleVertexClick(vertex.id)}
					/>
				{/if}

				<!-- Actual building -->
				{#if vertex.building}
					{@const color = getPlayerColor(vertex.building.player_id)}
					<g transform="translate({x}, {y})">
						{#if vertex.building.kind === 'Settlement'}
							<path
								d="M-8,4 L-8,-4 L0,-10 L8,-4 L8,4 Z"
								fill={color}
								stroke="#3E2723"
								stroke-width="1.5"
								class="drop-shadow-md"
							/>
						{:else if vertex.building.kind === 'City'}
							<path
								d="M-10,6 L-10,-2 L-4,-6 L-4,-2 L4,-2 L4,-8 L10,-12 L10,6 Z"
								fill={color}
								stroke="#3E2723"
								stroke-width="1.5"
								class="drop-shadow-md"
							/>
						{/if}
					</g>
				{/if}
			{/each}
		</g>
	</svg>
</div>
