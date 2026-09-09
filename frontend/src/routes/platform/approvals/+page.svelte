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
	};

	type DomainRow = {
		id: string;
		entity_id: string;
		entity_name: string;
		domain: string;
		created_at: string;
	};

	let rows = $state<Row[]>([]);
	let domainRows = $state<DomainRow[]>([]);
	let error = $state('');
	let feedback = $state<Record<string, string>>({});
	let domainFeedback = $state<Record<string, string>>({});

	onMount(async () => {
		const email = await requireSession();
		if (!email) {
			await goto('/');
			return;
		}
		try {
			const session = await api<SessionInfo>('/v1/session');
			if (!session.platform_admin) {
				error = 'Platform Super-Admin access is required.';
				return;
			}
			rows = await api<Row[]>('/v1/platform/registrations');
			domainRows = await api<DomainRow[]>('/v1/platform/domain-requests');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load approvals.';
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

	async function approveDomain(id: string) {
		error = '';
		try {
			await api(`/v1/platform/domain-requests/${id}/approve`, { method: 'POST' });
			domainRows = domainRows.filter((row) => row.id !== id);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Approve failed.';
		}
	}

	async function rejectDomain(id: string) {
		const text = (domainFeedback[id] || '').trim();
		if (!text) {
			error = 'Requester feedback is required to reject a domain addition.';
			return;
		}
		error = '';
		try {
			await api(`/v1/platform/domain-requests/${id}/reject`, {
				method: 'POST',
				body: JSON.stringify({ requester_feedback: text })
			});
			domainRows = domainRows.filter((row) => row.id !== id);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Reject failed.';
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
</script>

<svelte:head>
	<title>Approvals — Stufe7</title>
</svelte:head>

<div class="page">
	<header>
		<img src="/stufe7-logo.svg" alt="Stufe7" class="wordmark" />
		<a href="/app">Back to app</a>
	</header>
	<h1>Registration approvals</h1>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if !rows.length && !error}
		<p>No pending registrations.</p>
	{/if}
	{#each rows as row (row.id)}
		<article class="card">
			<h2>{row.company_name}</h2>
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
	<h1>Domain additions</h1>
	{#if !domainRows.length && !error}
		<p>No pending domain additions.</p>
	{/if}
	{#each domainRows as row (row.id)}
		<article class="card">
			<h2>{row.domain}</h2>
			<p>{row.entity_name}</p>
			<div class="actions">
				<button type="button" class="solid" onclick={() => approveDomain(row.id)}>Approve</button>
				<label>
					Requester feedback
					<textarea bind:value={domainFeedback[row.id]}></textarea>
				</label>
				<button type="button" class="ghost" onclick={() => rejectDomain(row.id)}>Reject</button>
			</div>
		</article>
	{/each}
</div>

<style>
	.page {
		min-height: 100vh;
		padding: 1.25rem 1rem 3rem;
		width: min(44rem, 100%);
		margin-inline: auto;
	}
	header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: 1.25rem;
	}
	.wordmark {
		height: 1.75rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.25rem;
		margin-bottom: 1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1,
	h2 {
		margin: 0 0 0.5rem;
	}
	p {
		margin: 0 0 0.5rem;
	}
	.muted {
		color: #5b607a;
		font-size: 0.9rem;
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
	.ghost,
	a {
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
	.ghost,
	a {
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
