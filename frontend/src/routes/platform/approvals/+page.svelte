<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Row = {
		id: string;
		company_name: string;
		work_email: string;
		country: string;
		reason_code: string | null;
		summary: string | null;
		status: string;
		created_at: string;
		stale?: boolean;
	};

	type ChangeRow = {
		id: string;
		request_type: string;
		entity_id: string;
		entity_name: string;
		summary: string;
		created_at: string;
		stale: boolean;
	};

	type WeekStat = {
		week_start: string;
		new_users: number;
		new_entities: number;
		active_entities: number;
		active_users: number;
		actions_created: number;
		from_rollup: boolean;
	};

	type DenyHealth = {
		refreshed_at: string | null;
		status: string | null;
		source_version: string | null;
		entry_count: number | null;
		error_summary: string | null;
	};

	let rows = $state<Row[]>([]);
	let changes = $state<ChangeRow[]>([]);
	let stats = $state<WeekStat[]>([]);
	let health = $state<DenyHealth | null>(null);
	let error = $state('');
	let feedback = $state<Record<string, string>>({});
	let changeFeedback = $state<Record<string, string>>({});

	const needsFeedback = (type: string) =>
		type === 'Domain Addition' || type === 'Domain Removal';

	onMount(async () => {
		const email = await requireSession();
		if (!email) {
			await goto('/');
			return;
		}
		try {
			const session = await api<SessionInfo>('/v1/session');
			if (!session.platform_admin && session.privacy_operator) {
				await goto('/platform/privacy');
				return;
			}
			if (!session.platform_admin) {
				error = 'Platform Super-Admin access is required.';
				return;
			}
			rows = await api<Row[]>('/v1/platform/registrations');
			changes = await api<ChangeRow[]>('/v1/platform/change-requests');
			stats = await api<WeekStat[]>('/v1/platform/stats');
			health = await api<DenyHealth>('/v1/platform/deny-health');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load platform console.';
		}
	});

	async function approve(id: string) {
		error = '';
		try {
			await api(`/v1/platform/registrations/${id}/approve`, { method: 'POST' });
			rows = rows.filter((row) => row.id !== id);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Approve failed.';
		}
	}

	async function reject(id: string) {
		const text = (feedback[id] || '').trim();
		if (!text) {
			error = 'Applicant feedback is required to reject.';
			return;
		}
		error = '';
		try {
			await api(`/v1/platform/registrations/${id}/reject`, {
				method: 'POST',
				body: JSON.stringify({ applicant_feedback: text })
			});
			rows = rows.filter((row) => row.id !== id);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Reject failed.';
		}
	}

	async function approveChange(id: string) {
		error = '';
		try {
			await api(`/v1/platform/change-requests/${id}/approve`, { method: 'POST' });
			changes = changes.filter((row) => row.id !== id);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Approve failed.';
		}
	}

	async function rejectChange(row: ChangeRow) {
		const text = (changeFeedback[row.id] || '').trim();
		if (needsFeedback(row.request_type) && !text) {
			error = 'Requester feedback is required to reject domain addition or removal.';
			return;
		}
		error = '';
		try {
			await api(`/v1/platform/change-requests/${row.id}/reject`, {
				method: 'POST',
				body: JSON.stringify({ requester_feedback: text })
			});
			changes = changes.filter((item) => item.id !== row.id);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Reject failed.';
		}
	}
</script>

<svelte:head>
	<title>Platform console — Stufe7</title>
</svelte:head>

<div class="page">
	<p class="muted">Counts only. Tenant CRM records are not shown here.</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}

	<h2>Weekly signup statistics</h2>
	{#if stats.length}
		<div class="table-wrap">
			<table>
				<thead>
					<tr>
						<th>Week (UTC)</th>
						<th>New users</th>
						<th>New entities</th>
						<th>Active entities</th>
						<th>Active users</th>
						<th>Actions</th>
						<th>Source</th>
					</tr>
				</thead>
				<tbody>
					{#each stats as row (row.week_start)}
						<tr>
							<td>{row.week_start.slice(0, 10)}</td>
							<td>{row.new_users}</td>
							<td>{row.new_entities}</td>
							<td>{row.active_entities}</td>
							<td>{row.active_users}</td>
							<td>{row.actions_created}</td>
							<td>{row.from_rollup ? 'rollup' : 'live'}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{/if}

	<h2>Deny-list refresh</h2>
	{#if health}
		<p>
			{health.status || 'none'}
			{#if health.refreshed_at}
				· {health.refreshed_at.slice(0, 16).replace('T', ' ')} UTC
			{/if}
			{#if health.entry_count != null}
				· {health.entry_count} entries
			{/if}
			{#if health.source_version}
				· {health.source_version.slice(0, 8)}
			{/if}
		</p>
		{#if health.error_summary}
			<p class="error">{health.error_summary}</p>
		{/if}
	{/if}

	<h2>Registration approvals</h2>
	{#if !rows.length && !error}
		<p>No pending registrations.</p>
	{/if}
	{#each rows as row (row.id)}
		<article class="card">
			<h3>{row.company_name}</h3>
			{#if row.stale}<p class="flag">Older than one day</p>{/if}
			<p>{row.work_email} · {row.country}</p>
			<p class="muted">{row.reason_code}: {row.summary}</p>
			<div class="actions">
				<button type="button" class="solid" onclick={() => approve(row.id)}>Approve</button>
				<label>
					Applicant feedback
					<textarea bind:value={feedback[row.id]}></textarea>
				</label>
				<button type="button" class="ghost" onclick={() => reject(row.id)}>Reject</button>
			</div>
		</article>
	{/each}

	<h2>Change requests</h2>
	{#if !changes.length && !error}
		<p>No pending domain or rename requests.</p>
	{/if}
	{#each changes as row (row.id)}
		<article class="card">
			<h3>{row.request_type}</h3>
			{#if row.stale}<p class="flag">Older than one day</p>{/if}
			<p>{row.entity_name}</p>
			<p class="muted">{row.summary}</p>
			<div class="actions">
				<button type="button" class="solid" onclick={() => approveChange(row.id)}>Approve</button>
				<label>
					Requester feedback
					<textarea bind:value={changeFeedback[row.id]}></textarea>
				</label>
				<button type="button" class="ghost" onclick={() => rejectChange(row)}>Reject</button>
			</div>
		</article>
	{/each}
</div>

<style>
	.page {
		min-height: calc(100vh - 4rem);
		padding: 1.25rem 1rem 3rem;
		width: min(52rem, 100%);
		margin-inline: auto;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.25rem;
		margin-bottom: 1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h2,
	h3 {
		margin: 0 0 0.5rem;
	}
	h2 {
		margin-top: 1.5rem;
	}
	p {
		margin: 0 0 0.5rem;
	}
	.muted {
		color: #5b607a;
		font-size: 0.9rem;
	}
	.flag {
		color: #8a5a12;
		background: #fff4d6;
		padding: 0.25rem 0.5rem;
		border-radius: 0.4rem;
		width: fit-content;
		font-size: 0.85rem;
		font-weight: 650;
	}
	.table-wrap {
		overflow-x: auto;
		background: white;
		border-radius: 1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.9rem;
	}
	th,
	td {
		text-align: left;
		padding: 0.55rem 0.7rem;
		border-bottom: 1px solid #eef0f6;
	}
	.actions {
		display: grid;
		gap: 0.65rem;
		margin-top: 0.75rem;
	}
	textarea {
		width: 100%;
		min-height: 4rem;
		font: inherit;
	}
	.solid,
	.ghost {
		border-radius: 999px;
		padding: 0.45rem 0.9rem;
		font: inherit;
		font-weight: 650;
		text-decoration: none;
		width: fit-content;
	}
	.solid {
		border: 0;
		background: #20265e;
		color: white;
		cursor: pointer;
	}
	.ghost {
		border: 1px solid #20265e;
		background: white;
		color: #20265e;
		cursor: pointer;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem 0.75rem;
		border-radius: 0.6rem;
	}
</style>
