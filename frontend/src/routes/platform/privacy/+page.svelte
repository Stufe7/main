<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Row = {
		id: string;
		subject_type: string;
		subject_id: string;
		entity_id: string | null;
		status: string;
		legal_basis: string;
		requested_at: string;
		executed_at: string | null;
	};

	let rows = $state<Row[]>([]);
	let subjectType = $state('CONTACT');
	let subjectId = $state('');
	let entityId = $state('');
	let legalBasis = $state('');
	let error = $state('');
	let info = $state('');

	async function load() {
		rows = await api<Row[]>('/v1/privacy/requests');
	}

	onMount(async () => {
		const email = await requireSession();
		if (!email) {
			await goto('/');
			return;
		}
		try {
			const session = await api<SessionInfo>('/v1/session');
			if (!session.privacy_operator) {
				error = 'Privacy operator access is required.';
				return;
			}
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load privacy requests.';
		}
	});

	async function execute(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			const result = await api<{ request_id: string }>('/v1/privacy/execute', {
				method: 'POST',
				body: JSON.stringify({
					subject_type: subjectType,
					subject_id: subjectId.trim(),
					entity_id: entityId.trim() || null,
					legal_basis: legalBasis.trim()
				})
			});
			info = `Executed ${result.request_id}.`;
			subjectId = '';
			legalBasis = '';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Execute failed.';
		}
	}
</script>

<svelte:head>
	<title>Privacy — Stufe7</title>
</svelte:head>

<div class="page">
	<p>
		Active privacy operators only. This is not an Entity Admin or Platform Super-Admin path. External
		requests arrive at privacy@stufe7.com.
	</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<form class="card" onsubmit={execute}>
		<label>Subject type
			<select bind:value={subjectType}>
				<option value="CONTACT">Contact</option>
				<option value="USER">User</option>
				<option value="REGISTRATION_REQUEST">Registration request</option>
			</select>
		</label>
		<label>Subject id
			<input bind:value={subjectId} required />
		</label>
		<label>Entity id (required for contacts)
			<input bind:value={entityId} />
		</label>
		<label>Legal basis
			<textarea bind:value={legalBasis} required></textarea>
		</label>
		<button type="submit">Execute anonymization</button>
	</form>
	<h2>Recent requests</h2>
	{#if !rows.length}
		<p>No privacy requests yet.</p>
	{/if}
	{#each rows as row (row.id)}
		<article class="card">
			<p><strong>{row.subject_type}</strong> {row.subject_id}</p>
			<p class="muted">
				{row.status} · {row.legal_basis} · {row.executed_at || row.requested_at}
			</p>
		</article>
	{/each}
</div>

<style>
	.page {
		min-height: calc(100vh - 4rem);
		padding: 1.25rem 1rem 3rem;
		width: min(44rem, 100%);
		margin-inline: auto;
	}
	.card,
	form,
	label {
		display: grid;
		gap: 0.45rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.25rem;
		margin-bottom: 1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	select,
	input,
	textarea,
	button {
		font: inherit;
	}
	input,
	select,
	textarea {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.4rem 0.55rem;
	}
	textarea {
		min-height: 4rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		padding: 0.45rem 0.9rem;
		font-weight: 650;
		background: #20265e;
		color: white;
		cursor: pointer;
		width: fit-content;
	}
	.muted {
		color: #5b607a;
		font-size: 0.9rem;
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
