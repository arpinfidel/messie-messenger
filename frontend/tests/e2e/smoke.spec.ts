import { expect, test } from '@playwright/test';

test.describe('App shell', () => {
  test('loads the landing page', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/Messie/i);
    await expect(page.getByRole('heading', { name: /Sign in to Matrix/i })).toBeVisible({ timeout: 10_000 });
  });
});
