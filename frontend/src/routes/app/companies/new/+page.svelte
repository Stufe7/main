<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type Company, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	let company_name = $state('');
	let country = $state('SG');
	let website = $state('');
	let error = $state('');

	onMount(async () => {
		if (!(await requireSession())) await goto('/');
		const session = await api<SessionInfo>('/v1/session');
		ensureActiveEntity(session.memberships);
	});

	async function submit(event: Event) {
		event.preventDefault();
		error = '';
		try {
			const created = await api<Company>('/v1/companies', {
				method: 'POST',
				body: JSON.stringify({
					company_name,
					country,
					website: website || null,
					status: 'Prospect'
				})
			});
			await goto(`/app/companies/${created.id}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not create company.';
		}
	}
</script>

<svelte:head>
	<title>Add company — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>Add company</h1>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	<form onsubmit={submit}>
		<label>Name <input bind:value={company_name} required /></label>
		<label>Country <input bind:value={country} maxlength="2" required /></label>
		<label>Website <input bind:value={website} placeholder="https://" /></label>
		<button type="submit">Create</button>
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
	button {
		font: inherit;
	}
	input {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.55rem 0.7rem;
	}
	button {
		margin-top: 0.5rem;
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
