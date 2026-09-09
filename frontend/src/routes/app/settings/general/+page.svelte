<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	const hours = Array.from({ length: 24 }, (_, hour) => `${String(hour).padStart(2, '0')}:00:00`);

	type DomainRow = {
		domain: string;
		status: string;
		is_primary: boolean;
		added_via: string;
	};

	type RequestRow = {
		id: string;
		request_type: string;
		domain: string | null;
		summary: string | null;
		status: string;
		requester_feedback: string | null;
		created_at: string;
	};

	let entityName = $state('');
	let legalName = $state('');
	let renameName = $state('');
	let renameLegal = $state('');
	let digestTime = $state('08:00:00');
	let domains = $state<DomainRow[]>([]);
	let requests = $state<RequestRow[]>([]);
	let addDomain = $state('');
	let error = $state('');
	let info = $state('');

	async function load() {
		const settings = await api<{
			entity_name: string;
			legal_name: string | null;
			digest_send_local_time: string;
		}>('/v1/settings/entity');
		entityName = settings.entity_name;
		legalName = settings.legal_name || '';
		renameName = settings.entity_name;
		renameLegal = settings.legal_name || '';
		digestTime = settings.digest_send_local_time.slice(0, 8);
		const payload = await api<{ domains: DomainRow[]; requests: RequestRow[] }>('/v1/domains');
		domains = payload.domains;
		requests = payload.requests;
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		const role = session.memberships.find(
			(row) => row.entity_id === ensureActiveEntity(session.memberships)
		)?.role;
		if (role !== 'Entity Admin') {
			error = 'Entity Admin access is required.';
			return;
		}
		try {
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load entity settings.';
		}
	});

	async function saveHour(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			await api('/v1/settings/entity', {
				method: 'PATCH',
				body: JSON.stringify({ digest_send_local_time: digestTime })
			});
			info = 'Digest send time saved.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		}
	}

	async function requestRename(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			await api('/v1/entity/rename', {
				method: 'POST',
				body: JSON.stringify({
					entity_name: renameName.trim(),
					legal_name: renameLegal.trim() || null
				})
			});
			info = 'Rename request submitted for platform review.';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Rename request failed.';
		}
	}

	async function requestAdd(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			await api('/v1/domains/requests', {
				method: 'POST',
				body: JSON.stringify({ domain: addDomain.trim() })
			});
			addDomain = '';
			info = 'Domain addition submitted for platform review.';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Addition request failed.';
		}
	}

	async function requestRemoval(domain: string) {
		error = '';
		info = '';
		try {
			await api('/v1/domains/removals', {
				method: 'POST',
				body: JSON.stringify({ domain })
			});
			info = `Removal of ${domain} submitted for platform review.`;
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Removal request failed.';
		}
	}

	async function requestPrimary(domain: string) {
		error = '';
		info = '';
		try {
			await api('/v1/domains/primary', {
				method: 'POST',
				body: JSON.stringify({ domain })
			});
			info = `Primary transfer to ${domain} submitted for platform review.`;
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Primary transfer request failed.';
		}
	}

	function label(row: RequestRow) {
		return row.summary || row.domain || row.request_type;
	}
</script>

<svelte:head>
	<title>Entity general — Stufe7</title>
</svelte:head>

<section class="wrap">
	<p>
		Display name and legal name are shown here. Changes wait for Platform Super-Admin review. Invites
		only succeed for Approved domains. The primary domain cannot be removed. After a new domain is
		approved, each member changes their own email in Account, then you can transfer primary and retire
		the old domain.
	</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}

	<section class="card">
		<h2>Entity</h2>
		<p class="muted">{entityName}{legalName ? ` · ${legalName}` : ''}</p>
		<form onsubmit={requestRename}>
			<label>Display name
				<input bind:value={renameName} required />
			</label>
			<label>Legal name
				<input bind:value={renameLegal} />
			</label>
			<button type="submit">Request rename</button>
		</form>
	</section>

	<section class="card">
		<h2>Digest send time</h2>
		<p class="muted">Whole hour for this entity. Each member receives it in their own timezone.</p>
		<form onsubmit={saveHour}>
			<label>Send time
				<select bind:value={digestTime}>
					{#each hours as hour (hour)}
						<option value={hour}>{hour.slice(0, 5)}</option>
					{/each}
				</select>
			</label>
			<button type="submit">Save</button>
		</form>
	</section>

	<section class="card">
		<h2>Approved email domains</h2>
		<ul>
			{#each domains as row (row.domain)}
				<li>
					<div>
						<strong>{row.domain}</strong>
						<span class="muted">
							{row.status}{row.is_primary ? ' · primary' : ''} · {row.added_via}
						</span>
					</div>
					{#if row.status === 'Approved'}
						<div class="row-actions">
							{#if !row.is_primary}
								<button type="button" class="ghost" onclick={() => requestPrimary(row.domain)}>
									Request primary
								</button>
								<button type="button" class="ghost" onclick={() => requestRemoval(row.domain)}>
									Request removal
								</button>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ul>
		<form onsubmit={requestAdd}>
			<label>Add domain
				<input bind:value={addDomain} placeholder="example.com" required />
			</label>
			<button type="submit">Request addition</button>
		</form>
	</section>

	<section class="card">
		<h2>Pending and recent requests</h2>
		{#if !requests.length}
			<p class="muted">None yet.</p>
		{/if}
		<ul>
			{#each requests as row (row.id)}
				<li>
					<strong>{row.request_type}</strong>
					<span class="muted">
						{label(row)} · {row.status}
						{#if row.requester_feedback}
							— {row.requester_feedback}
						{/if}
					</span>
				</li>
			{/each}
		</ul>
	</section>
</section>

<style>
	.wrap {
		width: min(44rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		display: grid;
		gap: 1rem;
	}
	.card,
	form,
	label {
		display: grid;
		gap: 0.5rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1,
	h2,
	p {
		margin: 0;
	}
	.muted {
		color: #5b607a;
		font-size: 0.92rem;
	}
	ul {
		list-style: none;
		padding: 0;
		margin: 0;
		display: grid;
		gap: 0.65rem;
	}
	li {
		display: grid;
		gap: 0.35rem;
	}
	.row-actions {
		display: flex;
		flex-wrap: wrap;
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
		padding: 0.4rem 0.55rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.45rem 0.9rem;
		width: fit-content;
		cursor: pointer;
	}
	.ghost {
		background: white;
		color: #20265e;
		border: 1px solid #20265e;
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
