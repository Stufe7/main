<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import AuthModal from '$lib/auth/AuthModal.svelte';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';
	import { setActiveEntityId } from '$lib/entity';

	type Preview = {
		email: string;
		role: string;
		status: string;
		entity_name: string;
		expires_at: string;
	};

	const invitationId = $derived(page.params.id);
	const invitePath = $derived(`/invite/${invitationId}`);
	const matching = $derived(
		Boolean(
			auth.ready &&
				auth.email &&
				invite &&
				auth.email.toLowerCase() === invite.email.toLowerCase()
		)
	);

	let invite = $state<Preview | null>(null);
	let error = $state('');
	let busy = $state(false);
	let authOpen = $state(false);
	let authTab = $state<'login' | 'signup'>('login');
	let ready = $state(false);

	onMount(async () => {
		try {
			invite = await api<Preview>(`/v1/invitations/${invitationId}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Invitation is not valid or has expired.';
			ready = true;
			return;
		}
		await requireSession();
		if (auth.email && auth.email.toLowerCase() !== invite.email.toLowerCase()) {
			await signOut();
		}
		authOpen = !auth.email;
		ready = true;
	});

	async function accept() {
		if (!matching) {
			authOpen = true;
			return;
		}
		busy = true;
		error = '';
		try {
			const result = await api<{ entity_id: string }>(`/v1/invitations/${invitationId}/accept`, {
				method: 'POST'
			});
			setActiveEntityId(result.entity_id);
			await goto('/app/companies');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Invitation cannot be accepted.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>Accept invitation — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>Join workspace</h1>
	{#if !ready}
		<p>Loading invitation…</p>
	{:else if invite}
		<p>
			{invite.email} is invited to {invite.entity_name} as {invite.role}. Sign in with that email,
			then accept. A one-time code is emailed.
		</p>
		{#if error}
			<p class="error">{error}</p>
		{/if}
		{#if matching}
			<button type="button" disabled={busy} onclick={accept}>Accept invitation</button>
		{:else}
			<button type="button" onclick={() => (authOpen = true)}>Email me a sign-in code</button>
		{/if}
	{:else}
		<p class="error">{error}</p>
		<p><a href="/">Back to Stufe7</a></p>
	{/if}
</section>

{#if invite}
	<AuthModal
		bind:open={authOpen}
		bind:tab={authTab}
		allowSignup={false}
		nextPath={invitePath}
		dismissible={true}
		allowedEmail={invite.email}
	/>
{/if}

<style>
	.card {
		width: min(28rem, calc(100% - 2rem));
		margin: 3rem auto;
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font: inherit;
		font-weight: 650;
		padding: 0.7rem 1rem;
		cursor: pointer;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
	a {
		color: #20265e;
	}
</style>
