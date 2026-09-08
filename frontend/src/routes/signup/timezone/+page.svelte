<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { requireSession } from '$lib/auth/session.svelte';
	import { readSignupDraft, writeSignupDraft } from '$lib/signup/draft';
	import { countryNeedsExplicitZone, listTimeZones, suggestedTimeZone } from '$lib/signup/timezones';

	let timezone = $state('');
	let zones = $state<string[]>([]);
	let country = $state('');
	let error = $state('');

	onMount(async () => {
		const draft = readSignupDraft();
		country = draft?.country ?? '';
		zones = listTimeZones(country);
		timezone = draft?.timezone || suggestedTimeZone(country);
		const email = await requireSession();
		if (!email) await goto('/');
	});

	async function submit(event: Event) {
		event.preventDefault();
		if (!timezone) {
			error = 'Choose a timezone to continue.';
			return;
		}
		const draft = readSignupDraft();
		if (draft) writeSignupDraft({ ...draft, timezone });
		await goto('/app');
	}
</script>

<svelte:head>
	<title>Confirm timezone — Stufe7</title>
</svelte:head>

<div class="page">
	<header>
		<img src="/stufe7-logo.svg" alt="Stufe7" class="wordmark" />
	</header>
	<form class="card" onsubmit={submit}>
		<h1>Your timezone</h1>
		<p>
			This becomes the company working calendar. It is suggested from your device
			{country ? ` and country ${country}` : ''}.
			{#if countryNeedsExplicitZone(country)}
				This country has more than one timezone — pick the one the company uses.
			{/if}
		</p>
		{#if error}
			<p class="error">{error}</p>
		{/if}
		<label>
			Timezone
			<select bind:value={timezone} required>
				{#each zones as zone (zone)}
					<option value={zone}>{zone}</option>
				{/each}
			</select>
		</label>
		<button class="solid" type="submit">Continue</button>
	</form>
</div>

<style>
	.page {
		min-height: 100vh;
		padding: 1.25rem 1rem 3rem;
	}
	header,
	.card {
		width: min(32rem, 100%);
		margin-inline: auto;
	}
	.wordmark {
		height: 1.75rem;
		width: auto;
		margin-bottom: 1.5rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
		display: grid;
		gap: 0.85rem;
	}
	h1 {
		margin: 0;
		font-size: 1.35rem;
	}
	p {
		margin: 0;
		color: #5b607a;
	}
	label {
		display: grid;
		gap: 0.35rem;
		font-size: 0.85rem;
		font-weight: 600;
	}
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.6rem;
		padding: 0.65rem 0.75rem;
		font: inherit;
		color: #20265e;
	}
	.solid {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font: inherit;
		font-weight: 650;
		padding: 0.75rem 1rem;
		cursor: pointer;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem 0.75rem;
		border-radius: 0.6rem;
	}
</style>
