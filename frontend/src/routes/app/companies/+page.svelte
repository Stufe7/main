<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, apiDownload, apiUpload, withActiveEntity, type Company } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	let rows = $state<Company[]>([]);
	let q = $state('');
	let error = $state('');
	let info = $state('');
	let loading = $state(true);
	let uploading = $state(false);

	async function load() {
		error = '';
		loading = true;
		try {
			const query = q.trim() ? `?q=${encodeURIComponent(q.trim())}` : '';
			rows = await api<Company[]>(`/v1/companies${query}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load companies.';
		} finally {
			loading = false;
		}
	}

	async function downloadSheet() {
		error = '';
		info = '';
		try {
			await apiDownload('/v1/companies/export', 'companies.xlsx');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not download Excel.';
		}
	}

	async function uploadSheet(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file) return;
		error = '';
		info = '';
		uploading = true;
		try {
			const result = await apiUpload<{
				added: number;
				updated: number;
				skipped: number;
				errors: string[];
			}>('/v1/companies/import', file);
			const extra = result.errors.length ? ` ${result.errors.slice(0, 5).join(' ')}` : '';
			info = `Added ${result.added}, updated ${result.updated}, skipped ${result.skipped}.${extra}`;
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not import Excel.';
		} finally {
			uploading = false;
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
			error = err instanceof Error ? err.message : 'Could not load companies.';
			loading = false;
		}
	});
</script>

<svelte:head>
	<title>Companies — Stufe7</title>
</svelte:head>

<section class="wrap">
	<div class="toolbar">
		<form
			onsubmit={(event) => {
				event.preventDefault();
				void load();
			}}
		>
			<input bind:value={q} placeholder="Search" />
			<button type="submit">Search</button>
		</form>
		<a href="/app/companies/new">Add company</a>
		<button type="button" class="ghost" onclick={downloadSheet}>Download Excel</button>
		<label class="ghost file">
			{uploading ? 'Uploading…' : 'Upload Excel'}
			<input type="file" accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" hidden onchange={uploadSheet} />
		</label>
	</div>
	<p class="hint">Download the current list, edit in Excel, then upload to add new companies and update existing ones. Keep Company ID for updates; leave it blank for new rows. Empty cells do not clear existing values.</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	{#if loading}
		<p>Loading…</p>
	{:else if !rows.length}
		<p>No companies match.</p>
	{:else}
		<ul class="list">
			{#each rows as row (row.id)}
				<li>
					<a href={`/app/companies/${row.id}`}>
						<strong>{row.company_name}</strong>
						<span>{row.status} · {row.country || '—'}</span>
					</a>
				</li>
			{/each}
		</ul>
		<p class="count">{rows.length} shown</p>
	{/if}
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
	.toolbar a:first-of-type {
		margin-left: auto;
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
	.toolbar a,
	.file {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.5rem 0.9rem;
		text-decoration: none;
		cursor: pointer;
	}
	.ghost,
	.file {
		background: white;
		color: #20265e;
		border: 1px solid #20265e;
	}
	.hint {
		color: #5b607a;
		font-size: 0.92rem;
		margin: 0 0 1rem;
	}
	.info {
		background: #eef7f1;
		color: #1e5c3a;
		padding: 0.65rem 0.75rem;
		border-radius: 0.6rem;
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
	li span {
		color: #5b607a;
		font-size: 0.9rem;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem 0.75rem;
		border-radius: 0.6rem;
	}
	.count {
		color: #5b607a;
	}
</style>
