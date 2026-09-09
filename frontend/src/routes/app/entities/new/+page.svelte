<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SignupComplete } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { setActiveEntityId } from '$lib/entity';
	import { COUNTRIES } from '$lib/signup/countries';
	import { listTimeZones, suggestedTimeZone } from '$lib/signup/timezones';

	let firstName = $state('');
	let lastName = $state('');
	let company = $state('');
	let country = $state('SG');
	let companyUrl = $state('https://');
	let timezone = $state(suggestedTimeZone('SG'));
	let error = $state('');

	const zones = $derived(listTimeZones(country));

	onMount(async () => {
		if (!(await requireSession())) await goto('/');
	});

	async function submit(event: Event) {
		event.preventDefault();
		error = '';
		try {
			const result = await api<SignupComplete>('/v1/signup/complete', {
				method: 'POST',
				body: JSON.stringify({
					first_name: firstName,
					last_name: lastName,
					company,
					country,
					company_url: companyUrl,
					timezone
				})
			});
			if (result.status === 'provisioned' && result.entity_id) {
				setActiveEntityId(result.entity_id);
				await goto('/app/companies');
				return;
			}
			await goto('/signup/pending');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not create entity.';
		}
	}
</script>

<svelte:head>
	<title>Create another entity — Stufe7</title>
</svelte:head>

<section class="card">
	<p>Uses the same identity check as signup. This login becomes Entity Admin of the new tenant.</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	<form onsubmit={submit}>
		<label>First name <input bind:value={firstName} required /></label>
		<label>Last name <input bind:value={lastName} required /></label>
		<label>Company <input bind:value={company} required /></label>
		<label>Country
			<select bind:value={country} onchange={() => (timezone = suggestedTimeZone(country))}>
				{#each COUNTRIES as item (item.code)}
					<option value={item.code}>{item.name}</option>
				{/each}
			</select>
		</label>
		<label>Company URL <input bind:value={companyUrl} required /></label>
		<label>Timezone
			<select bind:value={timezone}>
				{#each zones as zone (zone)}
					<option value={zone}>{zone}</option>
				{/each}
			</select>
		</label>
		<button type="submit">Create entity</button>
	</form>
</section>

<style>
	.card {
		width: min(32rem, calc(100% - 2rem));
		margin: 1.5rem auto;
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	form,
	label {
		display: grid;
		gap: 0.4rem;
	}
	input,
	select,
	button {
		font: inherit;
	}
	input,
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.55rem 0.7rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.7rem 1rem;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
</style>
