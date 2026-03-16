<script lang="ts">
	export let face: number;
	export let color: string = '#B22222'; // Default to brick red
</script>

<svg width="100%" height="100%" viewBox="0 0 100 100" class="drop-shadow-sm">
	<!-- Dice Body -->
	<rect x="5" y="5" width="90" height="90" rx="15" fill={color} stroke="#3E2723" stroke-width="2" />
	
	<!-- Inner Shadow/Highlight for 3D effect -->
	<rect x="8" y="8" width="84" height="84" rx="12" fill="none" stroke="#ffffff" stroke-width="2" stroke-opacity="0.3" />

	<!-- Pips -->
	<g fill="#ffffff">
		{#if face === 1}
			<circle cx="50" cy="50" r="8" />
		{:else if face === 2}
			<circle cx="30" cy="30" r="8" />
			<circle cx="70" cy="70" r="8" />
		{:else if face === 3}
			<circle cx="30" cy="30" r="8" />
			<circle cx="50" cy="50" r="8" />
			<circle cx="70" cy="70" r="8" />
		{:else if face === 4}
			<circle cx="30" cy="30" r="8" />
			<circle cx="70" cy="30" r="8" />
			<circle cx="30" cy="70" r="8" />
			<circle cx="70" cy="70" r="8" />
		{:else if face === 5}
			<circle cx="30" cy="30" r="8" />
			<circle cx="70" cy="30" r="8" />
			<circle cx="50" cy="50" r="8" />
			<circle cx="30" cy="70" r="8" />
			<circle cx="70" cy="70" r="8" />
		{:else if face === 6}
			<circle cx="30" cy="25" r="8" />
			<circle cx="70" cy="25" r="8" />
			<circle cx="30" cy="50" r="8" />
			<circle cx="70" cy="50" r="8" />
			<circle cx="30" cy="75" r="8" />
			<circle cx="70" cy="75" r="8" />
		{/if}
	</g>
</svg>
