<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';
	import { env } from '$env/dynamic/public';

	type Row = {
		index: number;
		company_name: string;
		flag: string;
		error: string | null;
		match_company_name: string | null;
		action: string;
	};

	type Preview = {
		filename: string;
		row_count: number;
		new_company_count: number;
		possible_duplicate_count: number;
		unmatched_owner_count: number;
		invalid_row_count: number;
		rows: Row[];
	};

	let preview = $state<Preview | null>(null);
	let ownerFallback = $state('null');
	let error = $state('');
	let info = $state('');
	const templateUrl = `${(env.PUBLIC_API_BASE_URL || '').replace(/\/$/, '')}/v1/imports/template`;

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		ensureActiveEntity(session.memberships);
	});

	async function readFile(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;
		error = '';
		info = '';
		const csv_text = await file.text();
		try {
			preview = await api<Preview>('/v1/imports/preview', {
				method: 'POST',
				body: JSON.stringify({ filename: file.name, csv_text })
			});
		} catch (err) {
			error = err instanceof Error ? err.message : 'Preview failed.';
		}
	}

	async function confirm() {
		if (!preview) return;
		error = '';
		try {
			const result = await api<{ imported_rows: number }>('/v1/imports/confirm', {
				method: 'POST',
				body: JSON.stringify({
					filename: preview.filename,
					owner_fallback: ownerFallback,
					rows: preview.rows
				})
			});
			info = `Imported ${result.imported_rows} rows.`;
			preview = null;
		} catch (err) {
			error = err instanceof Error ? err.message : 'Import failed.';
		}
	}
</script>

<svelte:head>
	<title>CSV import — Stufe7</title>
</svelte:head>

<section class="wrap">
	<p>Use the template. Duplicates are never merged automatically.</p>
	<p><a href={templateUrl}>Download template</a></p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<input type="file" accept=".csv,text/csv" onchange={readFile} />
	{#if preview}
		<p>
			{preview.row_count} rows · {preview.new_company_count} new ·
			{preview.possible_duplicate_count} possible duplicates ·
			{preview.unmatched_owner_count} unmatched owners ·
			{preview.invalid_row_count} invalid
		</p>
		<label>Unmatched owner fallback
			<select bind:value={ownerFallback}>
				<option value="null">Leave unassigned</option>
				<option value="self">Assign to me</option>
			</select>
		</label>
		<table>
			<thead>
				<tr>
					<th>#</th>
					<th>Company</th>
					<th>Flag</th>
					<th>Match</th>
					<th>Action</th>
				</tr>
			</thead>
			<tbody>
				{#each preview.rows as row (row.index)}
					<tr>
						<td>{row.index}</td>
						<td>{row.company_name}</td>
						<td>{row.flag}{row.error ? ` · ${row.error}` : ''}</td>
						<td>{row.match_company_name || '—'}</td>
						<td>
							{#if row.flag === 'invalid'}
								skip
							{:else}
								<select bind:value={row.action}>
									<option value="skip">Skip</option>
									<option value="create">Create new</option>
									{#if row.match_company_name}
										<option value="attach">Add contact to match</option>
									{/if}
								</select>
							{/if}
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
		<button type="button" onclick={confirm}>Confirm import</button>
	{/if}
</section>

<style>
	.wrap {
		width: min(64rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		display: grid;
		gap: 0.75rem;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		background: white;
		border-radius: 1rem;
		overflow: hidden;
	}
	th,
	td {
		text-align: left;
		padding: 0.55rem 0.7rem;
		border-bottom: 1px solid #eef0f6;
		font-size: 0.92rem;
	}
	select,
	button,
	input {
		font: inherit;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.55rem 0.9rem;
		width: fit-content;
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
