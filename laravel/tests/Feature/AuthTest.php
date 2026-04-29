<?php

namespace Tests\Feature;

use App\Models\Hospital;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Tests covering authentication failure paths.
 *
 * Failure modes exercised:
 *   - Missing required fields
 *   - Wrong password
 *   - Non-existent username
 *   - Disabled account
 *   - Accessing protected routes without a token
 *   - Accessing protected routes with a malformed token
 */
class AuthTest extends TestCase
{
    use RefreshDatabase;

    private Hospital $hospital;
    private User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->hospital = Hospital::factory()->create();
        $this->user     = User::factory()->create([
            'hospital_id' => $this->hospital->id,
            'password'    => bcrypt('correct-password'),
        ]);
    }

    // ── Login field validation ────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function login_fails_when_username_is_missing(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'password' => 'correct-password',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['username']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function login_fails_when_password_is_missing(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'username' => $this->user->username,
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['password']);
    }

    // ── Credential failures ───────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function login_fails_with_wrong_password(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'username' => $this->user->username,
            'password' => 'wrong-password',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['username']);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function login_fails_for_nonexistent_username(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'username' => 'does-not-exist',
            'password' => 'any-password',
        ]);

        $response->assertStatus(422)
                 ->assertJsonValidationErrors(['username']);
    }

    // ── Account state ─────────────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function login_fails_when_account_is_disabled(): void
    {
        // Correct credentials but account deactivated
        $inactive = User::factory()->inactive()->create([
            'hospital_id' => $this->hospital->id,
            'password'    => bcrypt('correct-password'),
        ]);

        $response = $this->postJson('/api/auth/login', [
            'username' => $inactive->username,
            'password' => 'correct-password',
        ]);

        $response->assertStatus(403)
                 ->assertJson(['error' => 'Account is disabled.']);
    }

    // ── Successful login sanity check ─────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function login_succeeds_with_valid_credentials(): void
    {
        $response = $this->postJson('/api/auth/login', [
            'username' => $this->user->username,
            'password' => 'correct-password',
        ]);

        $response->assertStatus(200)
                 ->assertJsonStructure(['token', 'user' => ['id', 'username', 'role', 'hospital_id']]);
    }

    // ── Protected route access ────────────────────────────────────────────────

    #[\PHPUnit\Framework\Attributes\Test]
    public function unauthenticated_request_to_protected_route_returns_401(): void
    {
        $this->getJson('/api/auth/me')->assertStatus(401);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function malformed_bearer_token_returns_401(): void
    {
        $this->withHeader('Authorization', 'Bearer totally-invalid-token')
             ->getJson('/api/auth/me')
             ->assertStatus(401);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function me_endpoint_returns_authenticated_user(): void
    {
        $response = $this->actingAs($this->user)->getJson('/api/auth/me');

        $response->assertStatus(200)
                 ->assertJsonPath('user.username', $this->user->username);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function logout_deletes_the_bearer_token_from_the_database(): void
    {
        $token = $this->user->createToken('test')->plainTextToken;
        $this->assertDatabaseCount('personal_access_tokens', 1);

        $this->withHeader('Authorization', "Bearer {$token}")
             ->postJson('/api/auth/logout')
             ->assertStatus(200)
             ->assertJson(['message' => 'Logged out.']);

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    #[\PHPUnit\Framework\Attributes\Test]
    public function logout_is_safe_when_authenticated_via_session_not_bearer_token(): void
    {
        // actingAs() gives a TransientToken (no DB row). Logout must not crash.
        $this->actingAs($this->user)
             ->postJson('/api/auth/logout')
             ->assertStatus(200)
             ->assertJson(['message' => 'Logged out.']);
    }
}
