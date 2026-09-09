<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type Company, type Contact, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	let companies = $state<Company[]>([]);
	let company_id = $state('');
	let first_name = $state('');
	let last_name = $state('');
	let job_title = $state('');
	let email = $state('');
	let error = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		ensureActiveEntity(session.memberships);
		const params = new URLSearchParams(location.search);
		company_id = params.get('company') || '';
		companies = await api<Company[]>('/v1/companies');
		if (!company_id && companies[0]) company_id = companies[0].id;
	});

	async function submit(event: Event) {
		event.preventDefault();
		error = '';
		try {
			const created = await api<Contact>('/v1/contacts', {
				method: 'POST',
				body: JSON.stringify({ company_id, first_name, last_name, job_title, email })
			});
			await goto(`/app/contacts/${created.id}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not create contact.';
		}
	}
</script>

<svelte:head>
	<title>Add contact — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>Add contact</h1>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	<form onsubmit={submit}>
		<label>Company
			<select bind:value={company_id} required>
				{#each companies as company (company.id)}
					<option value={company.id}>{company.company_name}</option>
				{/each}
			</select>
		</label>
		<label>First name <input bind:value={first_name} required /></label>
		<label>Last name <input bind:value={last_name} required /></label>
		<label>Job title <input bind:value={job_title} /></label>
		<label>Email <input type="email" bind:value={email} /></label>
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
