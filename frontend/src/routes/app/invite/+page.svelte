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

	type Member = {
		user_id: string;
		email: string;
		first_name: string | null;
		last_name: string | null;
		role: string;
		status: string;
	};

	type Person = {
		key: string;
		email: string;
		role: string;
		status: string;
	};

	let invites = $state<Invite[]>([]);
	let members = $state<Member[]>([]);
	let email = $state('');
	let role = $state('User');
	let error = $state('');
	let info = $state('');

	const people = $derived.by(() => {
		const taken = new Set(members.map((row) => row.email.toLowerCase()));
		const rows: Person[] = [];
		for (const invite of invites) {
			if (invite.status !== 'Pending' || taken.has(invite.email.toLowerCase())) continue;
			const expired = Date.parse(invite.expires_at) < Date.now();
			rows.push({
				key: invite.id,
				email: invite.email,
				role: invite.role,
				status: expired ? 'Expired' : 'Pending'
			});
		}
		for (const member of members) {
			if (member.status === 'removed') continue;
			rows.push({
				key: member.user_id,
				email: member.email,
				role: member.role,
				status: member.status === 'inactive' ? 'Inactive' : 'Active'
			});
		}
		return rows;
	});

	async function load() {
		invites = await api<Invite[]>('/v1/invitations');
		try {
			members = await api<Member[]>('/v1/users');
		} catch {
			members = [];
		}
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
			info = 'Invitation has been sent.';
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

<div class="page">
	<section class="card">
		<h2>Invite a colleague</h2>
		<p class="muted">Email domain must already be an Approved domain for this entity.</p>
		{#if error}
			<p class="error">{error}</p>
		{/if}
		{#if info}
			<p class="info">{info}</p>
		{/if}
		<form onsubmit={submit}>
			<label>Work email <input type="email" bind:value={email} required /></label>
			<label
				>Role
				<select bind:value={role}>
					<option>User</option>
					<option>Manager</option>
					<option>Entity Admin</option>
				</select>
			</label>
			<button type="submit">Send invite</button>
		</form>
	</section>

	<section class="card">
		<h2>People in this entity</h2>
		<p class="muted">Pending invites and current members. Deactivate or remove someone in Settings → Users.</p>
		{#if people.length}
			<table>
				<thead>
					<tr>
						<th>Email</th>
						<th>Role</th>
						<th>Status</th>
					</tr>
				</thead>
				<tbody>
					{#each people as row (row.key)}
						<tr>
							<td>{row.email}</td>
							<td>{row.role}</td>
							<td>{row.status}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		{:else}
			<p class="muted">No invitations or members to show yet.</p>
		{/if}
		<p><a href="/app/settings/users">Manage users</a></p>
	</section>
</div>

<style>
	.page {
		width: min(36rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		display: grid;
		gap: 1rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h2 {
		margin: 0 0 0.35rem;
		font-size: 1.15rem;
		color: #20265e;
	}
	.muted {
		margin: 0 0 1rem;
		color: #5b607a;
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
		margin-top: 0.35rem;
	}
	table {
		width: 100%;
		border-collapse: collapse;
	}
	th,
	td {
		text-align: left;
		padding: 0.55rem 0.2rem;
		border-bottom: 1px solid #eef0f6;
		font-size: 0.95rem;
	}
	th {
		color: #5b607a;
		font-weight: 650;
	}
	a {
		color: #20265e;
		font-weight: 650;
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
</style>
