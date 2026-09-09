<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Invite = {
		id: string;
		email: string;
		role: string;
		status: string;
		expires_at: string;
	};

	let rows = $state<Invite[]>([]);
	let email = $state('');
	let role = $state('User');
	let error = $state('');
	let info = $state('');

	async function load() {
		rows = await api<Invite[]>('/v1/invitations');
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load invitations.';
		}
	});

	async function submit(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			await api('/v1/invitations', {
				method: 'POST',
				body: JSON.stringify({ email, role })
			});
			info = 'Invitation recorded. They can open the link in the email, or use /invite/{id} after OTP login.';
			email = '';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Invite failed.';
		}
	}
</script>

<svelte:head>
	<title>Invite — Stufe7</title>
</svelte:head>

<section class="card">
	<p>Email domain must already be an Approved domain for this entity.</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<form onsubmit={submit}>
		<label>Work email <input type="email" bind:value={email} required /></label>
		<label>Role
			<select bind:value={role}>
				<option>User</option>
				<option>Manager</option>
				<option>Entity Admin</option>
			</select>
		</label>
		<button type="submit">Send invite</button>
	</form>
	<ul>
		{#each rows as row (row.id)}
			<li>{row.email} · {row.role} · {row.status}</li>
		{/each}
	</ul>
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
	.error,
	.info {
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
	}
	.info {
		background: #eef7f1;
		color: #1e5c3a;
	}
	ul {
		padding-left: 1.1rem;
	}
</style>
