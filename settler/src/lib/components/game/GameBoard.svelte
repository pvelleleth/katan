<script lang="ts">
	import { onMount } from 'svelte';
	import { Application, Container, Graphics, Text, TextStyle } from 'pixi.js';
	import {
		getLegalCityVertices,
		getLegalRoadEdges,
		getLegalRoadBuildingEdges,
		getLegalSettlementVertices
	} from './devCards';

	export let board: any;
	export let gameState: any;
	export let playerId: string;
	export let players: any[];
	export let sendGameAction: (action: string, payload?: any) => void;
	export let pendingBoardDevCardAction: 'knight' | 'road_building' | null = null;
	export let pendingBoardBuildAction: 'city' | null = null;
	export let roadBuildingSelection: string[] = [];
	export let onKnightTileSelect: (tileId: string) => void;
	export let onRoadBuildingEdgeSelect: (edgeId: string) => void;
	export let onCityVertexSelect: (vertexId: string) => void;

	type Point = { x: number; y: number };

	type TerrainPalette = {
		fill: number;
		shadow: number;
		highlight: number;
		icon: number;
	};

	let container: HTMLDivElement;
	let app: Application | null = null;
	let boardContainer: Container | null = null;
	let resizeObserver: ResizeObserver | null = null;

	const HEX_RADIUS = 72;
	const HEX_WIDTH = Math.sqrt(3) * HEX_RADIUS;
	const OCEAN_COLOR = '#0E6CA8';
	const BOARD_SAFE_X = 0.985;
	const BOARD_SAFE_Y = 0.985;

	const terrainPalette: Record<string, TerrainPalette> = {
		Wood: { fill: 0x1fa13e, shadow: 0x15752c, highlight: 0x53c96d, icon: 0x1a4d1f },
		Wheat: { fill: 0xe8c43a, shadow: 0xc9971f, highlight: 0xf3d96c, icon: 0xa06f10 },
		Sheep: { fill: 0x9ccb2f, shadow: 0x76a61e, highlight: 0xbdd95e, icon: 0x4c6721 },
		Brick: { fill: 0xe57a34, shadow: 0xc95f22, highlight: 0xf09a63, icon: 0x8b411d },
		Ore: { fill: 0xaeb3b6, shadow: 0x8c9296, highlight: 0xd7dcdf, icon: 0x596065 },
		Desert: { fill: 0xd6c991, shadow: 0xbaae76, highlight: 0xe6dbab, icon: 0x648434 }
	};

	const playerPieceColors: Record<string, number> = {
		brick: 0xe31d1d,
		ocean: 0x1f66f2,
		wheat: 0xf28a2a,
		purple: 0x27e33a,
		forest: 0x27e33a,
		wood: 0xf28a2a
	};

	const coastBands = [
		{ color: 0xd8f7fa, alpha: 0.72, width: HEX_RADIUS * 0.78 },
		{ color: 0x9fe5f0, alpha: 0.82, width: HEX_RADIUS * 0.58 },
		{ color: 0xe5c98c, alpha: 0.96, width: HEX_RADIUS * 0.4 }
	];

	function getPixelCoords(bx: number, by: number) {
		return {
			x: bx * ((HEX_RADIUS * Math.sqrt(3)) / 2),
			y: by * (HEX_RADIUS / 2)
		};
	}

	function getBoardCenter() {
		const points = board?.tiles?.map((tile: any) => getPixelCoords(tile.x, tile.y)) ?? [];
		if (points.length === 0) return { x: 0, y: 0 };

		const sum = points.reduce(
			(acc: Point, point: Point) => ({ x: acc.x + point.x, y: acc.y + point.y }),
			{ x: 0, y: 0 }
		);

		return { x: sum.x / points.length, y: sum.y / points.length };
	}

	function getPlayerColor(pId: string) {
		const player = players.find((entry) => entry.id === pId);
		return playerPieceColors[player?.color] ?? 0xe31d1d;
	}

	function getPips(token: number) {
		if (!token) return 0;
		return Math.max(0, 6 - Math.abs(7 - token));
	}

	function getHexPoints(radius: number, cx = 0, cy = 0) {
		const points: number[] = [];

		for (let i = 0; i < 6; i += 1) {
			const angle = -Math.PI / 6 + (Math.PI / 3) * i;
			points.push(cx + radius * Math.cos(angle), cy + radius * Math.sin(angle));
		}

		return points;
	}

	function drawHexShape(
		target: Graphics,
		radius: number,
		fill: number,
		strokeColor = 0x7a5b1a,
		strokeAlpha = 0.35,
		strokeWidth = 2
	) {
		target.poly(getHexPoints(radius)).fill(fill).stroke({
			width: strokeWidth,
			color: strokeColor,
			alpha: strokeAlpha,
			join: 'round'
		});
	}

	function clearBoard() {
		if (!boardContainer) return;

		for (const child of boardContainer.removeChildren()) {
			child.destroy({ children: true });
		}
	}

	function getVertexMap(): Map<string, Point> {
		return new Map<string, Point>(
			board.vertices.map((vertex: any) => [vertex.id, getPixelCoords(vertex.x, vertex.y)])
		);
	}

	function getVertexCoords(vertexId: string, vertexMap?: Map<string, Point>) {
		return vertexMap?.get(vertexId) ?? { x: 0, y: 0 };
	}

	function drawTileIcon(resource: string) {
		const icon = new Container();
		const g = new Graphics();
		const palette = terrainPalette[resource] ?? terrainPalette.Desert;
		const outline = 0x000000;

		if (resource === 'Wood') {
			g.poly([0, -24, 13, -7, 6, -7, 18, 9, -18, 9, -6, -7, -13, -7])
				.fill(0x3b922e)
				.stroke({ width: 1.4, color: outline, alpha: 0.25, join: 'round' });
			g.roundRect(-3.5, 9, 7, 14, 2)
				.fill(0x547c2b)
				.stroke({ width: 1.2, color: outline, alpha: 0.18 });
		} else if (resource === 'Wheat') {
			g.moveTo(0, 20)
				.quadraticCurveTo(0, 2, 0, -20)
				.stroke({ width: 2.5, color: 0x9a7a10, cap: 'round' });
			for (const offset of [-14, -8, -2, 4]) {
				g.poly([0, offset, -9, offset + 6, -2, offset + 11]).fill(0xebc53f);
				g.poly([0, offset, 9, offset + 6, 2, offset + 11]).fill(0xf4d56d);
			}
		} else if (resource === 'Sheep') {
			g.circle(-8, -2, 8).fill(0xffffff).stroke({ width: 1.2, color: outline, alpha: 0.18 });
			g.circle(0, -6, 10).fill(0xffffff).stroke({ width: 1.2, color: outline, alpha: 0.18 });
			g.circle(10, -1, 8).fill(0xffffff).stroke({ width: 1.2, color: outline, alpha: 0.18 });
			g.circle(1, 5, 7).fill(0xf1f1f1).stroke({ width: 1.2, color: outline, alpha: 0.18 });
			g.ellipse(19, -4, 6, 7).fill(0x9fa3a8).stroke({ width: 1.2, color: outline, alpha: 0.24 });
			g.moveTo(15, 8).lineTo(15, 18).stroke({ width: 2, color: 0x7a7a7a, cap: 'round' });
			g.moveTo(3, 9).lineTo(2, 18).stroke({ width: 2, color: 0x7a7a7a, cap: 'round' });
		} else if (resource === 'Brick') {
			const brickColor = 0xe9d2c4;
			g.roundRect(-21, -3, 42, 12, 3)
				.fill(brickColor)
				.stroke({ width: 1.2, color: 0x9d6842, alpha: 0.55 });
			g.roundRect(-15, -15, 14, 10, 3)
				.fill(brickColor)
				.stroke({ width: 1.2, color: 0x9d6842, alpha: 0.55 });
			g.roundRect(2, -15, 14, 10, 3)
				.fill(brickColor)
				.stroke({ width: 1.2, color: 0x9d6842, alpha: 0.55 });
			g.moveTo(0, -3).lineTo(0, 9).stroke({ width: 1, color: 0x9d6842, alpha: 0.45 });
			g.moveTo(-21, 3).lineTo(21, 3).stroke({ width: 1, color: 0x9d6842, alpha: 0.45 });
		} else if (resource === 'Ore') {
			g.poly([-23, 7, -11, -8, 2, 5]).fill(0xbfc4c5).stroke({ width: 1.2, color: outline, alpha: 0.18 });
			g.poly([-5, 12, 11, -11, 26, 5]).fill(0xdce0e1).stroke({ width: 1.2, color: outline, alpha: 0.18 });
			g.poly([-15, 3, -1, -16, 15, 2]).fill(0xebeeee).stroke({ width: 1.2, color: outline, alpha: 0.18 });
		} else {
			g.roundRect(-4, -20, 8, 34, 4)
				.fill(0x9b9a58)
				.stroke({ width: 1.2, color: outline, alpha: 0.2 });
			g.moveTo(-2, -8)
				.quadraticCurveTo(-15, -8, -15, -18)
				.stroke({ width: 4, color: 0x9b9a58, cap: 'round' });
			g.moveTo(2, -1)
				.quadraticCurveTo(16, -1, 16, -13)
				.stroke({ width: 4, color: 0x9b9a58, cap: 'round' });
		}

		icon.addChild(g);
		return icon;
	}

	function createTileDecor(resource: string) {
		const decor = new Container();
		const g = new Graphics();

		if (resource === 'Sheep' || resource === 'Wood' || resource === 'Wheat') {
			const grassColor = resource === 'Wood' ? 0x6ea422 : resource === 'Wheat' ? 0xe4cb60 : 0x77a71f;
			for (const [x, y] of [
				[-28, 2],
				[-22, -1],
				[-16, 3],
				[28, 0],
				[22, -4],
				[16, 2]
			]) {
				g.moveTo(x, y + 5)
					.lineTo(x - 4, y - 2)
					.moveTo(x, y + 5)
					.lineTo(x, y - 4)
					.moveTo(x, y + 5)
					.lineTo(x + 4, y - 1)
					.stroke({ width: 1.8, color: grassColor, alpha: 0.7, cap: 'round' });
			}
		}

		if (resource === 'Ore' || resource === 'Brick' || resource === 'Desert') {
			const rockColor = resource === 'Ore' ? 0x9ea4a8 : resource === 'Brick' ? 0xd28a8a : 0xc8af6b;
			for (const [x, y] of [
				[-34, 2],
				[-28, -2],
				[34, 4],
				[28, 0]
			]) {
				g.ellipse(x, y, 5, 3.2).fill({ color: rockColor, alpha: 0.82 });
				g.ellipse(x + 5, y - 2, 3.5, 2.6).fill({ color: rockColor, alpha: 0.72 });
			}
		}

		decor.addChild(g);
		return decor;
	}

	function createNumberToken(token: number) {
		const tokenContainer = new Container();
		const isHot = token === 6 || token === 8;
		const numberColor = isHot ? 0xd61e1e : 0x0e5b14;
		const shadow = new Graphics();
		const bg = new Graphics();
		const gloss = new Graphics();
		const label = new Text({
			text: String(token),
			style: new TextStyle({
				fontFamily: 'Nunito Sans, Arial Rounded MT Bold, Trebuchet MS, sans-serif',
				fontSize: 24,
				fontWeight: '900',
				fill: numberColor,
				align: 'center',
				letterSpacing: 0.5
			})
		});

		shadow.roundRect(-21, -18, 42, 34, 12).fill({ color: 0x000000, alpha: 0.12 });
		shadow.y = 2;

		bg.roundRect(-20, -19, 40, 32, 11)
			.fill(0xf1f1f1)
			.stroke({ width: 2, color: 0xc5c5c5, alpha: 1, join: 'round' });

		gloss.roundRect(-17, -16, 34, 11, 8).fill({ color: 0xffffff, alpha: 0.3 });

		label.anchor.set(0.5, 0.52);
		label.y = -4;

		tokenContainer.addChild(shadow);
		tokenContainer.addChild(bg);
		tokenContainer.addChild(gloss);
		tokenContainer.addChild(label);

		const pips = getPips(token);
		const pipSpacing = 5;
		const start = -((pips - 1) * pipSpacing) / 2;

		for (let index = 0; index < pips; index += 1) {
			const pip = new Graphics();
			pip.circle(start + index * pipSpacing, 8, 1.8).fill(numberColor);
			tokenContainer.addChild(pip);
		}

		return tokenContainer;
	}

	function createTileGraphics(tile: any) {
		const tileContainer = new Container();
		const palette = terrainPalette[tile.resource] ?? terrainPalette.Desert;

		const shadow = new Graphics();
		drawHexShape(shadow, HEX_RADIUS + 1, 0x8d651c, 0x8d651c, 0.12, 0);
		shadow.y = 2;

		const outerHex = new Graphics();
		drawHexShape(outerHex, HEX_RADIUS - 2, palette.shadow, 0x8c681a, 0.45, 2.4);

		const innerHex = new Graphics();
		drawHexShape(innerHex, HEX_RADIUS - 7, palette.fill, 0xffffff, 0.08, 1.2);

		const innerRim = new Graphics();
		innerRim.poly(getHexPoints(HEX_RADIUS - 10)).stroke({
			width: 3,
			color: palette.highlight,
			alpha: 0.9,
			join: 'round'
		});

		const shadingMask = new Graphics();
		shadingMask.poly(getHexPoints(HEX_RADIUS - 7)).fill(0xffffff);

		const shading = new Container();
		const topGlow = new Graphics();
		const centerGlow = new Graphics();
		const lowerShade = new Graphics();

		topGlow.ellipse(0, -22, HEX_RADIUS * 0.78, HEX_RADIUS * 0.28).fill({
			color: 0xffffff,
			alpha: 0.12
		});

		centerGlow.ellipse(0, 2, HEX_RADIUS * 0.88, HEX_RADIUS * 0.72).fill({
			color: palette.highlight,
			alpha: tile.resource === 'Desert' ? 0.28 : 0.17
		});

		lowerShade.ellipse(0, 35, HEX_RADIUS * 0.9, HEX_RADIUS * 0.34).fill({
			color: 0x000000,
			alpha: 0.08
		});

		shading.addChild(topGlow);
		shading.addChild(centerGlow);
		shading.addChild(lowerShade);
		shading.mask = shadingMask;

		const icon = drawTileIcon(tile.resource);
		icon.position.set(0, -HEX_RADIUS * 0.3);
		icon.scale.set(tile.resource === 'Desert' ? 0.86 : 0.82);

		const decor = createTileDecor(tile.resource);
		decor.position.set(0, -6);

		tileContainer.addChild(shadow);
		tileContainer.addChild(outerHex);
		tileContainer.addChild(innerHex);
		tileContainer.addChild(shading);
		tileContainer.addChild(shadingMask);
		tileContainer.addChild(innerRim);
		tileContainer.addChild(decor);
		tileContainer.addChild(icon);

		if (tile.token) {
			const token = createNumberToken(tile.token);
			token.position.set(0, HEX_RADIUS * 0.18);
			tileContainer.addChild(token);
		}

		if (tile.has_robber) {
			const robber = new Container();
			const robberShadow = new Graphics();
			const body = new Graphics();
			const head = new Graphics();
			const sash = new Graphics();
			const sheen = new Graphics();

			robberShadow.ellipse(0, 19, 12, 5).fill({ color: 0x000000, alpha: 0.15 });
			body
				.roundRect(-7, -11, 14, 30, 7)
				.fill(0x868686)
				.stroke({ width: 1.4, color: 0x5f5f5f, alpha: 0.9, join: 'round' });
			body
				.roundRect(-4.5, -24, 9, 18, 4.5)
				.fill(0x9a9a9a)
				.stroke({ width: 1.4, color: 0x5f5f5f, alpha: 0.9, join: 'round' });
			head.circle(0, -29, 6.5).fill(0xa8a8a8).stroke({ width: 1.3, color: 0x646464, alpha: 0.9 });
			sash.poly([-5, -5, 5, -11, 5, -6, -5, 0]).fill({ color: 0xb8b8b8, alpha: 0.55 });
			sheen.roundRect(-2, -32, 3, 11, 1.5).fill({ color: 0xdadada, alpha: 0.45 });

			robber.position.set(0, -1);
			robber.addChild(robberShadow);
			robber.addChild(body);
			robber.addChild(head);
			robber.addChild(sash);
			robber.addChild(sheen);
			tileContainer.addChild(robber);
		}

		return tileContainer;
	}

	function drawCoastline(vertexMap: Map<string, Point>) {
		const coastalEdges = board.edges.filter((edge: any) => (edge.tile_ids?.length ?? 0) === 1);
		const coastalVertexIds = new Set<string>();

		for (const edge of coastalEdges) {
			coastalVertexIds.add(edge.v1);
			coastalVertexIds.add(edge.v2);
		}

		const layers = coastBands.map((band) => {
			const g = new Graphics();

			for (const edge of coastalEdges) {
				const start = getVertexCoords(edge.v1, vertexMap);
				const end = getVertexCoords(edge.v2, vertexMap);
				g.moveTo(start.x, start.y)
					.lineTo(end.x, end.y)
					.stroke({ width: band.width, color: band.color, alpha: band.alpha, cap: 'round', join: 'round' });
			}

			for (const vertexId of coastalVertexIds) {
				const point = getVertexCoords(vertexId, vertexMap);
				g.circle(point.x, point.y, band.width / 2.3).fill({ color: band.color, alpha: band.alpha });
			}

			return g;
		});

		for (const layer of layers) {
			boardContainer?.addChild(layer);
		}
	}

	function createRoadGraphic(start: Point, end: Point, color: number) {
		const road = new Container();
		const dx = end.x - start.x;
		const dy = end.y - start.y;
		const length = Math.sqrt(dx * dx + dy * dy);
		const angle = Math.atan2(dy, dx);
		const thickness = HEX_RADIUS * 0.1;

		const shadow = new Graphics();
		shadow.roundRect(0, -thickness / 2, length, thickness, thickness / 2).fill({
			color: 0x000000,
			alpha: 0.12
		});
		shadow.y = 2;

		const body = new Graphics();
		body.roundRect(0, -thickness / 2, length, thickness, thickness / 2)
			.fill(color)
			.stroke({ width: 1.6, color: 0x6e5428, alpha: 0.45, join: 'round' });

		const highlight = new Graphics();
		highlight
			.roundRect(4, -thickness / 2 + 1.2, length - 8, thickness * 0.24, thickness * 0.18)
			.fill({ color: 0xffffff, alpha: 0.18 });

		road.position.set(start.x, start.y);
		road.rotation = angle;
		road.addChild(shadow);
		road.addChild(body);
		road.addChild(highlight);

		return road;
	}

	function createBuildingGraphic(kind: 'Settlement' | 'City', color: number) {
		const piece = new Container();
		const shadow = new Graphics();
		const body = new Graphics();
		const gloss = new Graphics();
		const door = new Graphics();

		if (kind === 'Settlement') {
			shadow.poly([-14, 10, -14, -2, 0, -18, 14, -2, 14, 10]).fill({ color: 0x000000, alpha: 0.14 });
			body.poly([-14, 10, -14, -2, 0, -18, 14, -2, 14, 10])
				.fill(color)
				.stroke({ width: 2, color: 0x3a2a16, alpha: 0.35, join: 'round' });
			gloss.poly([-8, 5, -8, -3, -1, -11, 8, -3, 8, 5]).fill({ color: 0xffffff, alpha: 0.18 });
			door.roundRect(-3.5, 1, 7, 9, 2).fill(0x4a321b);
		} else {
			shadow
				.poly([-18, 12, -18, -2, -7, -15, 3, -3, 3, -8, 18, -8, 18, 12])
				.fill({ color: 0x000000, alpha: 0.14 });
			body.poly([-18, 12, -18, -2, -7, -15, 3, -3, 3, -8, 18, -8, 18, 12])
				.fill(color)
				.stroke({ width: 2, color: 0x3a2a16, alpha: 0.35, join: 'round' });
			gloss.poly([-12, 7, -12, -1, -6, -9, 0, -1, 0, -5, 12, -5, 12, 7]).fill({
				color: 0xffffff,
				alpha: 0.18
			});
			door.roundRect(-2, 0, 7, 12, 2).fill(0x4a321b);
		}

		shadow.y = 2;
		piece.addChild(shadow);
		piece.addChild(body);
		piece.addChild(gloss);
		piece.addChild(door);

		return piece;
	}

	function harborLabel(kind: string) {
		if (kind === 'ThreeToOne') return { text: '3:1', icon: null };
		if (kind === 'WoodTwoToOne') return { text: '2:1', icon: 'Wood' };
		if (kind === 'BrickTwoToOne') return { text: '2:1', icon: 'Brick' };
		if (kind === 'SheepTwoToOne') return { text: '2:1', icon: 'Sheep' };
		if (kind === 'WheatTwoToOne') return { text: '2:1', icon: 'Wheat' };
		if (kind === 'OreTwoToOne') return { text: '2:1', icon: 'Ore' };
		return { text: '3:1', icon: null };
	}

	function createHarbor(harbor: any, vertexMap: Map<string, Point>, boardCenter: Point) {
		const v1 = getVertexCoords(harbor.vertex_ids[0], vertexMap);
		const v2 = getVertexCoords(harbor.vertex_ids[1], vertexMap);
		const mid = { x: (v1.x + v2.x) / 2, y: (v1.y + v2.y) / 2 };
		const edgeDx = v2.x - v1.x;
		const edgeDy = v2.y - v1.y;
		const edgeLength = Math.sqrt(edgeDx * edgeDx + edgeDy * edgeDy) || 1;
		const tx = edgeDx / edgeLength;
		const ty = edgeDy / edgeLength;
		const dirX = mid.x - boardCenter.x;
		const dirY = mid.y - boardCenter.y;
		const dirLength = Math.sqrt(dirX * dirX + dirY * dirY) || 1;
		const nx = dirX / dirLength;
		const ny = dirY / dirLength;
		const dockBase = { x: mid.x + nx * 14, y: mid.y + ny * 14 };
		const dockTop = { x: mid.x + nx * 44, y: mid.y + ny * 44 };
		const gangwayStart = { x: mid.x + nx * 30 + tx * 16, y: mid.y + ny * 30 + ty * 16 };
		const gangwayEnd = { x: mid.x + nx * 66 + tx * 6, y: mid.y + ny * 66 + ty * 6 };
		const shipPos = { x: mid.x + nx * 95, y: mid.y + ny * 95 };
		const rotation = Math.atan2(ny, nx) + Math.PI / 2;
		const harborContainer = new Container();

		const dock = new Graphics();
		dock.moveTo(dockBase.x - tx * 9, dockBase.y - ty * 9)
			.lineTo(dockTop.x - tx * 9, dockTop.y - ty * 9)
			.stroke({ width: 4.5, color: 0xb67b25, alpha: 1, cap: 'round' });
		dock.moveTo(dockBase.x + tx * 9, dockBase.y + ty * 9)
			.lineTo(dockTop.x + tx * 9, dockTop.y + ty * 9)
			.stroke({ width: 4.5, color: 0xb67b25, alpha: 1, cap: 'round' });

		for (let step = 0; step <= 1; step += 0.18) {
			const x = dockBase.x + (dockTop.x - dockBase.x) * step;
			const y = dockBase.y + (dockTop.y - dockBase.y) * step;
			dock.moveTo(x - tx * 10, y - ty * 10)
				.lineTo(x + tx * 10, y + ty * 10)
				.stroke({ width: 2.1, color: 0x8b5d18, alpha: 0.95, cap: 'round' });
		}

		dock.moveTo(gangwayStart.x, gangwayStart.y)
			.lineTo(gangwayEnd.x, gangwayEnd.y)
			.stroke({ width: 15, color: 0xb67b25, alpha: 1, cap: 'butt' });
		for (let step = 0.08; step <= 0.92; step += 0.18) {
			const x = gangwayStart.x + (gangwayEnd.x - gangwayStart.x) * step;
			const y = gangwayStart.y + (gangwayEnd.y - gangwayStart.y) * step;
			dock.moveTo(x - nx * 8, y - ny * 8)
				.lineTo(x + nx * 8, y + ny * 8)
				.stroke({ width: 2.1, color: 0x8b5d18, alpha: 0.92, cap: 'round' });
		}

		const ship = new Container();
		const hullShadow = new Graphics();
		const hull = new Graphics();
		const mast = new Graphics();
		const sail = new Graphics();
		const foam = new Graphics();
		const label = harborLabel(harbor.kind);

		foam.ellipse(0, 17, 18, 5).fill({ color: 0xd8f7fa, alpha: 0.9 });
		foam.ellipse(-6, 20, 9, 3).fill({ color: 0xffffff, alpha: 0.4 });
		foam.ellipse(7, 20, 9, 3).fill({ color: 0xffffff, alpha: 0.35 });

		hullShadow.ellipse(0, 13, 20, 5).fill({ color: 0x000000, alpha: 0.1 });
		hull
			.poly([-18, 2, 18, 2, 13, 8, -13, 8])
			.fill(0xc07f2a)
			.stroke({ width: 2, color: 0x8b5d18, alpha: 0.85, join: 'round' });
		hull.roundRect(-12, -1, 24, 4, 2).fill(0xe0a44f);
		mast.moveTo(0, 2).lineTo(0, -33).stroke({ width: 2.2, color: 0x8b5d18, cap: 'round' });
		sail.poly([0, -30, 0, 1, 19, -4]).fill(0xffffff).stroke({
			width: 1.5,
			color: 0xd7d7d7,
			alpha: 1,
			join: 'round'
		});

		const sailMark = new Container();
		if (label.icon) {
			const icon = drawTileIcon(label.icon);
			icon.scale.set(0.19);
			icon.position.set(7, -14);
			sailMark.addChild(icon);
		}

		const text = new Text({
			text: label.text,
			style: new TextStyle({
				fontFamily: 'Nunito Sans, Arial Rounded MT Bold, Trebuchet MS, sans-serif',
				fontSize: 10,
				fontWeight: '900',
				fill: 0x6a4a22,
				align: 'center'
			})
		});
		text.anchor.set(0.5);
		text.position.set(7, label.icon ? -2 : -12);
		sailMark.addChild(text);

		ship.position.set(shipPos.x, shipPos.y);
		ship.rotation = rotation;
		ship.addChild(foam);
		ship.addChild(hullShadow);
		ship.addChild(hull);
		ship.addChild(mast);
		ship.addChild(sail);
		ship.addChild(sailMark);

		harborContainer.addChild(dock);
		harborContainer.addChild(ship);
		return harborContainer;
	}

	function getBoardBounds() {
		if (!board?.tiles?.length) {
			return { minX: -100, maxX: 100, minY: -100, maxY: 100 };
		}

		const tilePoints = board.tiles.map((tile: any) => getPixelCoords(tile.x, tile.y));
		let minX = Math.min(...tilePoints.map((point: Point) => point.x - HEX_WIDTH * 0.68));
		let maxX = Math.max(...tilePoints.map((point: Point) => point.x + HEX_WIDTH * 0.68));
		let minY = Math.min(...tilePoints.map((point: Point) => point.y - HEX_RADIUS * 1.2));
		let maxY = Math.max(...tilePoints.map((point: Point) => point.y + HEX_RADIUS * 1.2));

		if (board.harbors?.length) {
			const vertexMap = getVertexMap();
			const center = getBoardCenter();

			for (const harbor of board.harbors) {
				const v1 = getVertexCoords(harbor.vertex_ids[0], vertexMap);
				const v2 = getVertexCoords(harbor.vertex_ids[1], vertexMap);
				const mid = { x: (v1.x + v2.x) / 2, y: (v1.y + v2.y) / 2 };
				const nx = mid.x - center.x;
				const ny = mid.y - center.y;
				const len = Math.sqrt(nx * nx + ny * ny) || 1;
				const px = mid.x + (nx / len) * 95;
				const py = mid.y + (ny / len) * 95;
				minX = Math.min(minX, px - 24);
				maxX = Math.max(maxX, px + 24);
				minY = Math.min(minY, py - 38);
				maxY = Math.max(maxY, py + 24);
			}
		}

		return {
			minX: minX - HEX_RADIUS * 0.18,
			maxX: maxX + HEX_RADIUS * 0.18,
			minY: minY - HEX_RADIUS * 0.18,
			maxY: maxY + HEX_RADIUS * 0.18
		};
	}

	function centerBoard() {
		if (!app || !boardContainer) return;

		const bounds = getBoardBounds();
		const boardWidth = bounds.maxX - bounds.minX;
		const boardHeight = bounds.maxY - bounds.minY;
		const scale = Math.min(
			(app.screen.width * BOARD_SAFE_X) / boardWidth,
			(app.screen.height * BOARD_SAFE_Y) / boardHeight
		);

		boardContainer.scale.set(scale);
		boardContainer.position.set(
			app.screen.width / 2 - ((bounds.minX + boardWidth / 2) * scale),
			app.screen.height / 2 - ((bounds.minY + boardHeight / 2) * scale)
		);
	}

	function renderBoard() {
		if (!app || !boardContainer || !board || !gameState) return;

		clearBoard();

		const vertexMap = getVertexMap();
		const boardCenter = getBoardCenter();
		const isMyTurn = gameState.turn.current_player_id === playerId;
		const phase = gameState.turn.phase;
		const myGamePlayer = gameState.players.find((player: any) => player.id === playerId);

		const canPlaceSettlement =
			isMyTurn &&
			(phase === 'Setup1Settlement' || phase === 'Setup2Settlement' || phase === 'Main') &&
			(myGamePlayer?.settlements_left ?? 0) > 0;
		const canPlaceRoad =
			isMyTurn &&
			(phase === 'Setup1Road' ||
				phase === 'Setup2Road' ||
				phase === 'Main' ||
				pendingBoardDevCardAction === 'road_building') &&
			(myGamePlayer?.roads_left ?? 0) > 0;
		const canMoveRobber =
			isMyTurn && (phase === 'MoveRobber' || pendingBoardDevCardAction === 'knight');
		const canPlaceCity = isMyTurn && phase === 'Main' && pendingBoardBuildAction === 'city';
		const showNormalRoadTargets = canPlaceRoad && pendingBoardDevCardAction !== 'road_building';
		const legalRoadEdgeIds = new Set(getLegalRoadEdges(board, playerId, phase).map((edge) => edge.id));
		const legalRoadBuildingEdgeIds = new Set(
			getLegalRoadBuildingEdges(
				pendingBoardDevCardAction === 'road_building' ? board : null,
				playerId,
				roadBuildingSelection,
				myGamePlayer?.roads_left ?? 0
			).map((edge) => edge.id)
		);
		const legalSettlementVertexIds = new Set(
			getLegalSettlementVertices(board, playerId, phase).map((vertex) => vertex.id)
		);
		const legalCityVertexIds = new Set(
			getLegalCityVertices(board, playerId).map((vertex) => vertex.id)
		);

		drawCoastline(vertexMap);

		for (const tile of board.tiles) {
			const tilePosition = getPixelCoords(tile.x, tile.y);
			const tileContainer = createTileGraphics(tile);
			tileContainer.position.set(tilePosition.x, tilePosition.y);

			if (canMoveRobber && !tile.has_robber) {
				tileContainer.eventMode = 'static';
				tileContainer.cursor = 'pointer';
				tileContainer.on('pointerover', () => {
					tileContainer.alpha = 0.88;
				});
				tileContainer.on('pointerout', () => {
					tileContainer.alpha = 1;
				});
				tileContainer.on('pointerdown', () => {
					if (pendingBoardDevCardAction === 'knight') {
						onKnightTileSelect(tile.id);
						return;
					}

					sendGameAction('move_robber', { tile_id: tile.id });
				});
			}

			boardContainer.addChild(tileContainer);
		}

		for (const edge of board.edges) {
			const v1 = getVertexCoords(edge.v1, vertexMap);
			const v2 = getVertexCoords(edge.v2, vertexMap);
			const isRoadBuildingSelected = roadBuildingSelection.includes(edge.id);
			const isRoadBuildingCandidate =
				pendingBoardDevCardAction === 'road_building' && legalRoadBuildingEdgeIds.has(edge.id);
			const isNormalCandidate = showNormalRoadTargets && legalRoadEdgeIds.has(edge.id);
			const edgeContainer = new Container();

			if (edge.road) {
				const dx = v2.x - v1.x;
				const dy = v2.y - v1.y;
				const len = Math.sqrt(dx * dx + dy * dy) || 1;
				const inset = HEX_RADIUS * 0.11;
				const start = { x: v1.x + (dx / len) * inset, y: v1.y + (dy / len) * inset };
				const end = { x: v2.x - (dx / len) * inset, y: v2.y - (dy / len) * inset };
				edgeContainer.addChild(createRoadGraphic(start, end, getPlayerColor(edge.road.player_id)));
			}

			if (isRoadBuildingSelected) {
				const selected = new Graphics();
				selected
					.moveTo(v1.x, v1.y)
					.lineTo(v2.x, v2.y)
					.stroke({ width: 11, color: 0xffec82, alpha: 0.88, cap: 'round' });
				edgeContainer.addChild(selected);
			} else if (isRoadBuildingCandidate || isNormalCandidate) {
				const indicator = new Graphics();
				const hitArea = new Graphics();

				indicator
					.moveTo(v1.x, v1.y)
					.lineTo(v2.x, v2.y)
					.stroke({ width: 7, color: 0xffffff, alpha: 0.45, cap: 'round' });
				hitArea
					.moveTo(v1.x, v1.y)
					.lineTo(v2.x, v2.y)
					.stroke({ width: 20, color: 0xffffff, alpha: 0.01, cap: 'round' });

				edgeContainer.addChild(indicator);
				edgeContainer.addChild(hitArea);
				edgeContainer.eventMode = 'static';
				edgeContainer.cursor = 'pointer';
				edgeContainer.on('pointerover', () => {
					indicator.alpha = 0.9;
				});
				edgeContainer.on('pointerout', () => {
					indicator.alpha = 0.45;
				});
				edgeContainer.on('pointerdown', () => {
					if (pendingBoardDevCardAction === 'road_building') {
						onRoadBuildingEdgeSelect(edge.id);
						return;
					}

					sendGameAction('place_road', { edge_id: edge.id, free: phase.startsWith('Setup') });
				});
			}

			boardContainer.addChild(edgeContainer);
		}

		for (const vertex of board.vertices) {
			const point = getVertexCoords(vertex.id, vertexMap);
			const vertexContainer = new Container();
			vertexContainer.position.set(point.x, point.y);

			if (vertex.building) {
				const kind = vertex.building.kind === 'Settlement' ? 'Settlement' : 'City';
				vertexContainer.addChild(createBuildingGraphic(kind, getPlayerColor(vertex.building.player_id)));
			}

			const isSettlementCandidate =
				canPlaceSettlement && !vertex.building && legalSettlementVertexIds.has(vertex.id);
			const isCityCandidate = canPlaceCity && legalCityVertexIds.has(vertex.id);

			if (isSettlementCandidate || isCityCandidate) {
				const indicator = new Graphics();
				const hitArea = new Graphics();
				const radius = isCityCandidate ? 22 : 16;

				indicator.circle(0, 0, radius).stroke({ width: 3, color: 0xffffff, alpha: 0.5 });
				hitArea.circle(0, 0, 20).fill({ color: 0xffffff, alpha: 0.01 });

				vertexContainer.addChild(indicator);
				vertexContainer.addChild(hitArea);
				vertexContainer.eventMode = 'static';
				vertexContainer.cursor = 'pointer';
				vertexContainer.on('pointerover', () => {
					indicator.alpha = 1;
				});
				vertexContainer.on('pointerout', () => {
					indicator.alpha = 0.5;
				});
				vertexContainer.on('pointerdown', () => {
					if (isCityCandidate) {
						onCityVertexSelect(vertex.id);
						return;
					}

					sendGameAction('place_settlement', {
						vertex_id: vertex.id,
						free: phase.startsWith('Setup')
					});
				});
			}

			boardContainer.addChild(vertexContainer);
		}

		if (board.harbors?.length) {
			for (const harbor of board.harbors) {
				boardContainer.addChild(createHarbor(harbor, vertexMap, boardCenter));
			}
		}

		centerBoard();
	}

	onMount(() => {
		app = new Application();

		app
			.init({
				background: OCEAN_COLOR,
				resizeTo: container,
				antialias: true,
				resolution: window.devicePixelRatio || 1,
				autoDensity: true
			})
			.then(() => {
				if (!app) return;
				container.appendChild(app.canvas);
				boardContainer = new Container();
				app.stage.addChild(boardContainer);
				renderBoard();
			});

		resizeObserver = new ResizeObserver(() => {
			centerBoard();
		});
		resizeObserver.observe(container);

		return () => {
			resizeObserver?.disconnect();
			resizeObserver = null;
			app?.destroy(true, { children: true, texture: true });
			app = null;
			boardContainer = null;
		};
	});

	$: if (app && boardContainer && board && gameState) {
		renderBoard();
	}
</script>

<div bind:this={container} class="h-full w-full"></div>
