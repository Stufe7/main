<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Payload = {
		domains: { domain: string; status: string; is_primary: boolean; added_via: string }[];
		requests: {
			id: string;
			domain: string;
			status: string;
			requester_feedback: string | null;
			created_at: string;
		}[];
	};

	let data = $state<Payload | null>(null);
	let domain = $state('');
	let error = $state('');

	async function load() {
		data = await api<Payload>('/v1/domains');
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load domains.';
		}
	});

	async function submit(event: Event) {
		event.preventDefault();
		error = '';
		try {
			await api('/v1/domains/requests', {
				method: 'POST',
				body: JSON.stringify({ domain })
			});
			domain = '';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Request failed.';
		}
	}
</script>

<svelte:head>
	<title>Approved email domains — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>Approved email domains</h1>
	<p>Invites only succeed for Approved domains. Additions wait for Platform Super-Admin review.</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if data}
		<ul>
			{#each data.domains as row (row.domain)}
				<li>
					<strong>{row.domain}</strong>
					{row.status}{row.is_primary ? ' · primary' : ''}
				</li>
			{/each}
		</ul>
		<h2>Requests</h2>
		<ul>
			{#each data.requests as row (row.id)}
				<li>
					{row.domain} · {row.status}
					{#if row.requester_feedback}
						— {row.requester_feedback}
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
	<form onsubmit={submit}>
		<label>Add domain <input bind:value={domain} placeholder="example.com" required /></label>
		<button type="submit">Request addition</button>
	</form>
</section>

<style>
	.card {
		width: min(36rem, calc(100% - 2rem));
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
