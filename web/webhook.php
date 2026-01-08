<?php
/**
 * Cipi Centralized Webhook Handler
 *
 * Receives GitHub webhooks, validates signatures using HMAC-SHA256,
 * and triggers deployments for the specified app.
 */

// Configuration
define('WEBHOOKS_FILE', '/etc/cipi/webhooks.json');
define('APPS_FILE', '/etc/cipi/apps.json');
define('LOG_FILE', '/var/log/cipi/webhook.log');

// Ensure log directory exists
if (!is_dir(dirname(LOG_FILE))) {
    mkdir(dirname(LOG_FILE), 0755, true);
}

/**
 * Log a message to the webhook log file
 */
function webhook_log($message, $level = 'INFO') {
    $timestamp = date('Y-m-d H:i:s');
    $log_entry = "[$timestamp] [$level] $message\n";
    file_put_contents(LOG_FILE, $log_entry, FILE_APPEND | LOCK_EX);
}

/**
 * Send JSON response and exit
 */
function respond($status_code, $message, $details = []) {
    http_response_code($status_code);
    header('Content-Type: application/json');
    echo json_encode(array_merge(['status' => $status_code >= 400 ? 'error' : 'success', 'message' => $message], $details));
    exit;
}

/**
 * Validate GitHub webhook signature using HMAC-SHA256
 */
function validate_github_signature($payload, $secret, $signature_header) {
    if (empty($signature_header)) {
        return false;
    }

    // GitHub sends signature as "sha256=<hash>"
    if (strpos($signature_header, 'sha256=') !== 0) {
        return false;
    }

    $expected_signature = 'sha256=' . hash_hmac('sha256', $payload, $secret);

    // Use timing-safe comparison to prevent timing attacks
    return hash_equals($expected_signature, $signature_header);
}

/**
 * Get the username from the request URI
 */
function get_username_from_uri() {
    $uri = $_SERVER['REQUEST_URI'] ?? '';

    // Remove query string if present
    $uri = strtok($uri, '?');

    // Match /webhook/<username>
    if (preg_match('#^/webhook/([a-zA-Z0-9_-]+)/?$#', $uri, $matches)) {
        return $matches[1];
    }

    return null;
}

/**
 * Check if app exists
 */
function app_exists($username) {
    if (!file_exists(APPS_FILE)) {
        return false;
    }

    $apps = json_decode(file_get_contents(APPS_FILE), true);
    return isset($apps[$username]);
}

/**
 * Get webhook secret for an app
 */
function get_webhook_secret($username) {
    if (!file_exists(WEBHOOKS_FILE)) {
        return null;
    }

    $webhooks = json_decode(file_get_contents(WEBHOOKS_FILE), true);
    return $webhooks[$username]['secret'] ?? null;
}

/**
 * Trigger deployment for an app
 */
function trigger_deployment($username) {
    $home_dir = "/home/$username";
    $deploy_script = "$home_dir/deploy.sh";

    if (!file_exists($deploy_script)) {
        webhook_log("Deploy script not found: $deploy_script", 'ERROR');
        return ['success' => false, 'error' => 'Deploy script not found'];
    }

    // Run deployment as the app user
    $command = sprintf(
        'sudo -u %s bash -c "cd %s && ./deploy.sh" 2>&1',
        escapeshellarg($username),
        escapeshellarg($home_dir)
    );

    $output = [];
    $return_code = 0;
    exec($command, $output, $return_code);

    $output_str = implode("\n", $output);

    if ($return_code === 0) {
        webhook_log("Deployment successful for $username", 'INFO');
        return ['success' => true, 'output' => $output_str];
    } else {
        webhook_log("Deployment failed for $username: $output_str", 'ERROR');
        return ['success' => false, 'error' => 'Deployment failed', 'output' => $output_str];
    }
}

// ============================================
// Main Request Handler
// ============================================

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    webhook_log("Invalid request method: " . $_SERVER['REQUEST_METHOD'], 'WARN');
    respond(405, 'Method not allowed. Use POST.');
}

// Check Content-Type header (warn but don't reject - GitHub always sends JSON payload)
$content_type = $_SERVER['CONTENT_TYPE'] ?? $_SERVER['HTTP_CONTENT_TYPE'] ?? '';
if (stripos($content_type, 'application/json') === false && stripos($content_type, 'json') === false) {
    webhook_log("Unexpected Content-Type: $content_type (continuing anyway)", 'WARN');
}

// Get username from URL
$username = get_username_from_uri();
if (!$username) {
    webhook_log("Invalid webhook URL: " . ($_SERVER['REQUEST_URI'] ?? 'unknown'), 'WARN');
    respond(400, 'Invalid webhook URL. Expected /webhook/<username>');
}

webhook_log("Webhook received for: $username");

// Check if app exists
if (!app_exists($username)) {
    webhook_log("App not found: $username", 'WARN');
    respond(404, 'App not found');
}

// Get webhook secret
$secret = get_webhook_secret($username);
if (!$secret) {
    webhook_log("No webhook secret configured for: $username", 'WARN');
    respond(401, 'Webhook not configured for this app');
}

// Get request payload
$payload = file_get_contents('php://input');
if (empty($payload)) {
    webhook_log("Empty payload received for: $username", 'WARN');
    respond(400, 'Empty payload');
}

// Check payload size limit (10MB)
if (strlen($payload) > 10485760) {
    webhook_log("Payload too large for: $username (size: " . strlen($payload) . ")", 'WARN');
    respond(413, 'Payload too large. Maximum size is 10MB.');
}

// Get GitHub signature header
$signature = $_SERVER['HTTP_X_HUB_SIGNATURE_256'] ?? '';

// Validate signature
if (!validate_github_signature($payload, $secret, $signature)) {
    webhook_log("Invalid signature for: $username", 'WARN');
    respond(401, 'Invalid signature');
}

webhook_log("Signature validated for: $username");

// Check GitHub event type
$event = $_SERVER['HTTP_X_GITHUB_EVENT'] ?? 'unknown';

// Handle ping event (sent when webhook is created)
if ($event === 'ping') {
    webhook_log("Ping received for: $username");
    respond(200, 'Pong! Webhook configured successfully.', ['app' => $username]);
}

// Only process push events
if ($event !== 'push') {
    webhook_log("Ignoring event type '$event' for: $username");
    respond(200, "Event '$event' acknowledged but not processed.", ['app' => $username, 'event' => $event]);
}

// Parse payload to get event details
$data = json_decode($payload, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    webhook_log("Invalid JSON payload for: $username - " . json_last_error_msg(), 'WARN');
    respond(400, 'Invalid JSON payload: ' . json_last_error_msg());
}

$ref = $data['ref'] ?? 'unknown';
$pusher = $data['pusher']['name'] ?? 'unknown';
$repo = $data['repository']['full_name'] ?? 'unknown';

webhook_log("Push event: $repo ($ref) by $pusher");

// Send response to GitHub immediately, then run deployment
// This prevents GitHub timeout while still running deployment synchronously
header('Content-Type: application/json');
http_response_code(200);
echo json_encode([
    'status' => 'ok',
    'message' => 'Deployment started',
    'app' => $username,
    'ref' => $ref,
    'repository' => $repo
]);

// Flush output and close connection to GitHub
if (function_exists('fastcgi_finish_request')) {
    fastcgi_finish_request();
} else {
    // Fallback for non-FPM environments
    ob_end_flush();
    flush();
}

// Now run deployment (GitHub won't wait for this)
$result = trigger_deployment($username);

if ($result['success']) {
    webhook_log("Deployment completed for $username", 'INFO');
} else {
    webhook_log("Deployment failed for $username: " . ($result['error'] ?? 'Unknown'), 'ERROR');
}
