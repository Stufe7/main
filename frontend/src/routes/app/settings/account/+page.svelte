<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { getSupabase } from '$lib/supabase/client';

	let currentEmail = $state('');
	let nextEmail = $state('');
	let busy = $state(false);
	let error = $state('');
	let info = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			const session = await api<SessionInfo>('/v1/session');
			currentEmail = session.email || '';
			if (session.email_sync_error) {
				error = `${session.email_sync_error} Contact support@stufe7.com.`;
			}
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load account.';
		}
	});

	async function startChange(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		const email = nextEmail.trim().toLowerCase();
		if (!email || email === currentEmail.toLowerCase()) {
			error = 'Enter a different email address.';
			return;
		}
		const supabase = getSupabase();
		if (!supabase) {
			error = 'Authentication is not connected in this environment yet.';
			return;
		}
		busy = true;
		try {
			await api('/v1/account/email-change/start', {
				method: 'POST',
				body: JSON.stringify({ email })
			});
			const redirectTo = `${window.location.origin}/app/settings/account`;
			const { error: authError } = await supabase.auth.updateUser(
				{ email },
				{ emailRedirectTo: redirectTo }
			);
			if (authError) {
				error = authError.message;
				return;
			}
			info = `Check ${email} for a confirmation from noreply@. The account email updates only after you confirm.`;
			nextEmail = '';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not start the email change.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>Account — Stufe7</title>
</svelte:head>

<section class="wrap">
	<h1>Account</h1>
	<p>
		Email change is all-or-nothing across every remaining membership. The new domain must already be
		Approved for each of those entities. A colliding address is never merged — contact
		support@stufe7.com.
	</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<form onsubmit={startChange}>
		<p class="muted">Current email: {currentEmail || '—'}</p>
		<label>New email
			<input type="email" bind:value={nextEmail} required autocomplete="email" />
		</label>
		<button type="submit" disabled={busy}>{busy ? 'Sending…' : 'Change email'}</button>
	</form>
</section>

<style>
	.wrap,
	form,
	label {
		display: grid;
		gap: 0.65rem;
	}
	.wrap {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	form {
		background: white;
		border-radius: 1rem;
		padding: 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1,
	p {
		margin: 0;
	}
	.muted {
		color: #5b607a;
		font-size: 0.92rem;
	}
	input,
	button {
		font: inherit;
	}
	input {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.4rem 0.55rem;
		width: 100%;
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
	button:disabled {
		opacity: 0.65;
		cursor: wait;
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
