<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	type UserRow = {
		user_id: string;
		email: string;
		first_name: string | null;
		last_name: string | null;
		role: string;
		status: string;
		last_accessed_at: string | null;
		deactivated_at: string | null;
	};

	type Work = { kind: string; id: string; label: string };

	const roles = ['User', 'Manager', 'Entity Admin'];

	let rows = $state<UserRow[]>([]);
	let error = $state('');
	let info = $state('');
	let target = $state<UserRow | null>(null);
	let work = $state<Work[]>([]);
	let defaultTo = $state('');
	let overrides = $state<Record<string, string>>({});

	const activeOthers = $derived(
		rows.filter((row) => row.status === 'active' && row.user_id !== target?.user_id)
	);

	async function load() {
		rows = await api<UserRow[]>('/v1/users');
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		if (!ensureActiveEntity(session.memberships)) {
			error = 'No entity membership.';
			return;
		}
		try {
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load users.';
		}
	});

	function nameOf(row: UserRow) {
		return [row.first_name, row.last_name].filter(Boolean).join(' ') || row.email;
	}

	async function changeRole(row: UserRow, role: string) {
		error = '';
		info = '';
		if (role === row.role) return;
		try {
			await api(`/v1/users/${row.user_id}/role`, {
				method: 'PATCH',
				body: JSON.stringify({ role })
			});
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Role change failed.';
		}
	}

	async function startDeactivate(row: UserRow) {
		error = '';
		info = '';
		target = row;
		work = await api<Work[]>(`/v1/users/${row.user_id}/responsibilities`);
		defaultTo = '';
		overrides = {};
	}

	async function confirmDeactivate(event: Event) {
		event.preventDefault();
		if (!target) return;
		error = '';
		const companies: Record<string, string> = {};
		const actions: Record<string, string> = {};
		const campaigns: Record<string, string> = {};
		const campaign_companies: Record<string, string> = {};
		for (const item of work) {
			const chosen = overrides[`${item.kind}:${item.id}`];
			if (!chosen) continue;
			if (item.kind === 'company') companies[item.id] = chosen;
			if (item.kind === 'action') actions[item.id] = chosen;
			if (item.kind === 'campaign') campaigns[item.id] = chosen;
			if (item.kind === 'campaign_company') campaign_companies[item.id] = chosen;
		}
		try {
			await api(`/v1/users/${target.user_id}/deactivate`, {
				method: 'POST',
				body: JSON.stringify({
					default_to_user_id: defaultTo || null,
					companies,
					actions,
					campaigns,
					campaign_companies
				})
			});
			info = `${nameOf(target)} is inactive.`;
			target = null;
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Deactivate failed.';
		}
	}

	async function reactivate(row: UserRow) {
		error = '';
		try {
			await api(`/v1/users/${row.user_id}/reactivate`, { method: 'POST' });
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Reactivate failed.';
		}
	}

	async function remove(row: UserRow) {
		error = '';
		try {
			await api(`/v1/users/${row.user_id}/remove`, { method: 'POST' });
			info = `${nameOf(row)} is removed from this entity.`;
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Remove failed.';
		}
	}
</script>

<svelte:head>
	<title>Users — Stufe7</title>
</svelte:head>

<section class="wrap">
	<p>Entity Admins can change role, deactivate with a split handover, reactivate, or remove.</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<table>
		<thead>
			<tr>
				<th>User</th>
				<th>Email</th>
				<th>Role</th>
				<th>Status</th>
				<th>Last access</th>
				<th></th>
			</tr>
		</thead>
		<tbody>
			{#each rows as row (row.user_id)}
				<tr>
					<td>{nameOf(row)}</td>
					<td>{row.email}</td>
					<td>
						{#if row.status === 'removed'}
							{row.role}
						{:else}
							<select value={row.role} onchange={(event) => changeRole(row, event.currentTarget.value)}>
								{#each roles as role}
									<option>{role}</option>
								{/each}
							</select>
						{/if}
					</td>
					<td>{row.status}</td>
					<td>{row.last_accessed_at ? row.last_accessed_at.slice(0, 16).replace('T', ' ') : '—'}</td>
					<td class="actions">
						{#if row.status === 'active'}
							<button type="button" onclick={() => startDeactivate(row)}>Deactivate</button>
						{/if}
						{#if row.status === 'inactive'}
							<button type="button" onclick={() => reactivate(row)}>Reactivate</button>
							<button type="button" class="danger" onclick={() => remove(row)}>Remove</button>
						{/if}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>

	{#if target}
		<section class="card">
			<h2>Deactivate {nameOf(target)}</h2>
			{#if work.length}
				<p>Assign current work to active replacements. Default applies unless a row is overridden.</p>
				<form onsubmit={confirmDeactivate}>
					<label>Default replacement
						<select bind:value={defaultTo} required>
							<option value="">Select…</option>
							{#each activeOthers as row (row.user_id)}
								<option value={row.user_id}>{nameOf(row)}</option>
							{/each}
						</select>
					</label>
					{#each work as item (item.kind + item.id)}
						<label>{item.kind}: {item.label}
							<select bind:value={overrides[`${item.kind}:${item.id}`]}>
								<option value="">Use default</option>
								{#each activeOthers as row (row.user_id)}
									<option value={row.user_id}>{nameOf(row)}</option>
								{/each}
							</select>
						</label>
					{/each}
					<button type="submit">Deactivate and reassign</button>
					<button type="button" class="ghost" onclick={() => (target = null)}>Cancel</button>
				</form>
			{:else}
				<p>No owned companies, open actions, or campaigns. Access will stop for this entity.</p>
				<form onsubmit={confirmDeactivate}>
					<button type="submit">Deactivate</button>
					<button type="button" class="ghost" onclick={() => (target = null)}>Cancel</button>
				</form>
			{/if}
		</section>
	{/if}
</section>

<style>
	.wrap {
		width: min(64rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		background: white;
		border-radius: 1rem;
		overflow: hidden;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	th,
	td {
		text-align: left;
		padding: 0.7rem 0.85rem;
		border-bottom: 1px solid #eef0f6;
		font-size: 0.95rem;
	}
	.actions {
		display: flex;
		gap: 0.4rem;
		flex-wrap: wrap;
	}
	.card,
	form,
	label {
		display: grid;
		gap: 0.45rem;
	}
	.card {
		margin-top: 1.25rem;
		background: white;
		border-radius: 1rem;
		padding: 1rem 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	select,
	button {
		font: inherit;
	}
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.4rem 0.55rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.4rem 0.8rem;
		cursor: pointer;
		width: fit-content;
	}
	.ghost {
		background: white;
		color: #20265e;
		border: 1px solid #20265e;
	}
	.danger {
		background: #8a1f1f;
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
