<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, withActiveEntity, type Contact } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	let rows = $state<Contact[]>([]);
	let q = $state('');
	let error = $state('');

	async function load() {
		error = '';
		try {
			const query = q.trim() ? `?q=${encodeURIComponent(q.trim())}` : '';
			rows = await api<Contact[]>(`/v1/contacts${query}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load contacts.';
		}
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			await withActiveEntity(load);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load contacts.';
		}
	});
</script>

<svelte:head>
	<title>Contacts — Stufe7</title>
</svelte:head>

<section class="wrap">
	<div class="toolbar">
		<h1>Contacts</h1>
		<form
			onsubmit={(event) => {
				event.preventDefault();
				void load();
			}}
		>
			<input bind:value={q} placeholder="Search" />
			<button type="submit">Search</button>
		</form>
		<a href="/app/contacts/new">Add contact</a>
	</div>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	<ul class="list">
		{#each rows as row (row.id)}
			<li>
				<a href={`/app/contacts/${row.id}`}>
					<strong>{row.first_name} {row.last_name}</strong>
					<span>{row.company_name} · {row.job_title || '—'}</span>
				</a>
			</li>
		{/each}
	</ul>
</section>

<style>
	.wrap {
		width: min(52rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	.toolbar {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem;
		align-items: center;
		margin-bottom: 1rem;
	}
	h1 {
		margin: 0 auto 0 0;
	}
	form {
		display: flex;
		gap: 0.4rem;
	}
	input,
	button,
	a {
		font: inherit;
	}
	input {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.5rem 0.7rem;
	}
	button,
	.toolbar a {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.5rem 0.9rem;
		text-decoration: none;
	}
	.list {
		list-style: none;
		padding: 0;
		margin: 0;
		background: white;
		border-radius: 1rem;
		overflow: hidden;
	}
	li a {
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		padding: 0.85rem 1rem;
		border-bottom: 1px solid #eef0f6;
		color: inherit;
		text-decoration: none;
	}
	span {
		color: #5b607a;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
</style>
