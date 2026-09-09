<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';
	import { readSignupDraft } from '$lib/signup/draft';

	let draft = $state<ReturnType<typeof readSignupDraft>>(null);

	onMount(async () => {
		const email = await requireSession();
		if (!email) {
			await goto('/');
			return;
		}
		draft = readSignupDraft();
	});

	async function leave() {
		await signOut();
		await goto('/');
	}
</script>

<svelte:head>
	<title>Registration pending — Stufe7</title>
</svelte:head>

<div class="page">
	<header>
		<img src="/stufe7-logo.svg" alt="Stufe7" class="wordmark" />
		{#if auth.email}
			<p class="who">{auth.email}</p>
			<button type="button" class="ghost" onclick={leave}>Sign out</button>
		{/if}
	</header>
	<section class="card">
		<h1>Registration is being reviewed</h1>
		<p>
			Your company identity could not be verified automatically.
			{#if draft}
				{draft.company} is waiting for an administrator decision. You will be able to sign in
				once it is approved.
			{:else}
				An administrator will email you when a decision is made.
			{/if}
		</p>
	</section>
</div>

<style>
	.page {
		min-height: 100vh;
		padding: 1.25rem 1rem 3rem;
	}
	header,
	.card {
		width: min(40rem, 100%);
		margin-inline: auto;
	}
	header {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.75rem 1rem;
		margin-bottom: 1.5rem;
	}
	.wordmark {
		height: 1.75rem;
		width: auto;
	}
	.who {
		margin: 0 auto 0 0;
		color: #5b607a;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1 {
		margin: 0 0 0.75rem;
		font-size: 1.5rem;
	}
	p {
		margin: 0;
		color: #3c4160;
	}
	.ghost {
		border: 1px solid #20265e;
		background: white;
		color: #20265e;
		border-radius: 999px;
		padding: 0.45rem 0.9rem;
		font: inherit;
		font-weight: 650;
		cursor: pointer;
	}
</style>
