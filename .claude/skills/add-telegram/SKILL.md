---
name: add-telegram
description: Add Telegram as a communication channel (replace WhatsApp, additional channel, control channel, or action-only)
---

# Add Telegram Integration

This skill adds Telegram capabilities to NanoClaw. It can be configured in four modes:

1. **Replace WhatsApp** - Telegram becomes the primary channel
2. **Additional Channel** - Run alongside WhatsApp
3. **Control Channel** - Telegram triggers actions, WhatsApp continues
4. **Action-Only** - Used for notifications triggered elsewhere

## Initial Questions

Ask the user:

> How do you want to use Telegram with NanoClaw?
>
> **Option 1: Replace WhatsApp**
> - Telegram becomes your primary channel
> - All agent interactions go through Telegram instead of WhatsApp
>
> **Option 2: Additional Channel**
> - Run both Telegram and WhatsApp simultaneously
> - Switch between channels as needed
> - Same agent context across both
>
> **Option 3: Control Channel**
> - Telegram is for sending commands and trigger actions
> - WhatsApp remains the primary channel
> - Use Telegram when you need quick access
>
> **Option 4: Action-Only**
> - Telegram is used only for notifications/alerts
> - No incoming messages (no handler needed)
> - Triggered from scheduled tasks or other channels

Store their choice and proceed to the appropriate section.

---

## Prerequisites (All Modes)

### 1. Install Telegraf Library

```bash
npm install telegraf
```

### 2. Create Telegram Bot

Tell the user:

> I need you to create a Telegram bot. Here's how:
>
> 1. Open Telegram and search for `@BotFather`
> 2. Click on it and start a chat
> 3. Send: `/newbot`
> 4. Follow the prompts:
>    - **"Give your bot a name:"** - Something friendly (e.g., "My NanoClaw Bot")
>    - **"Give your bot a username:"** - Must end with "bot" (e.g., "my_nanoclaw_bot")
> 5. BotFather will give you a token - it looks like: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`
> 6. **COPY THIS TOKEN** - you'll need it in a moment

Wait for user to complete this.

### 3. Store Bot Token

Tell the user:

> Now I'll save your bot token. You can either:
> - Tell me the token and I'll save it
> - Or point me to a file where you saved it
>
> Where is your token?

If user provides the token directly:

```bash
export TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234..."
```

Then save it to `.env`:

```bash
echo 'TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234..."' >> .env
```

Verify it's set:

```bash
grep TELEGRAM_BOT_TOKEN .env
```

### 4. Get Your Chat ID (For Action-Only Mode)

Tell the user:

> If you're using action-only mode, I need your personal chat ID. Here's how to find it:
>
> 1. Message your bot (find it in Telegram by its username)
> 2. Send it any message
> 3. Run this command:

```bash
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" | jq '.result[0].message.chat.id'
```

> Copy the number you get - that's your chat ID.

For groups, the user will need to add the bot and note the group ID (negative number).

---

## Replace WhatsApp Mode

Replace WhatsApp entirely with Telegram.

### Step 1: Add Telegram Handler

Read `src/index.ts` and find where WhatsApp is initialized (look for `connectWhatsApp` or similar).

At the top of the file, add the Telegraf import:

```typescript
import { Telegraf } from 'telegraf';
```

Create the bot instance after your logger setup:

```typescript
const telegrafBot = new Telegraf(process.env.TELEGRAM_BOT_TOKEN!);
```

Add this message handler (before any WhatsApp code or replacing it):

```typescript
// Telegram message handler
telegrafBot.on('message', async (ctx) => {
  if (!ctx.message || !('text' in ctx.message)) return;
  
  const chatId = String(ctx.chat.id);
  const isGroup = ctx.chat.type === 'group' || ctx.chat.type === 'supergroup';
  
  // Extract sender information
  const senderId = String(ctx.from?.id || ctx.chat.id);
  const senderName = ctx.from?.first_name || ctx.from?.username || 'User';
  
  logger.info(
    { chatId, isGroup, senderName },
    `Telegram message: ${ctx.message.text}`
  );
  
  try {
    // Show typing indicator
    await telegrafBot.telegram.sendChatAction(chatId, 'typing');
    
    // Process message through existing routing
    // (adapt to your existing message handler)
    await processIncomingMessage({
      chatId,
      sender: senderId,
      senderName,
      content: ctx.message.text,
      timestamp: ctx.message.date * 1000,
      isGroup,
      platform: 'telegram'
    });
  } catch (error) {
    logger.error({ error, chatId }, 'Error processing Telegram message');
    await telegrafBot.telegram.sendMessage(chatId, 'Sorry, something went wrong.');
  }
});
```

Add these helper functions after the bot setup:

```typescript
async function sendTelegramMessage(chatId: string, text: string): Promise<void> {
  try {
    await telegrafBot.telegram.sendMessage(chatId, text);
  } catch (error) {
    logger.error({ error, chatId }, 'Failed to send Telegram message');
    throw error;
  }
}

async function setTelegramTyping(chatId: string): Promise<void> {
  try {
    await telegrafBot.telegram.sendChatAction(chatId, 'typing');
  } catch (error) {
    logger.error({ error, chatId }, 'Failed to set typing indicator');
  }
}
```

### Step 2: Start the Bot

Find where WhatsApp or other services start their connection. Replace or add (in `src/index.ts`):

```typescript
// Start Telegram bot
try {
  telegrafBot.launch();
  logger.info('Telegram bot started');
  
  process.once('SIGINT', () => {
    logger.info('Shutting down Telegram bot');
    telegrafBot.stop('SIGINT');
  });
  process.once('SIGTERM', () => {
    logger.info('Shutting down Telegram bot');
    telegrafBot.stop('SIGTERM');
  });
} catch (error) {
  logger.error({ error }, 'Failed to start Telegram bot');
  process.exit(1);
}
```

### Step 3: Remove WhatsApp Code

Find and comment out or delete:
- `connectWhatsApp()` function calls
- WhatsApp-specific message handlers
- WhatsApp initialization code

Keep the existing `processIncomingMessage` or agent routing function - just wire Telegram to it instead.

### Step 4: Update Group Memory

Update `groups/main/CLAUDE.md`:

```markdown
## Communication

You are accessed via Telegram. Users send you messages in their chat or group, and you respond to them.

Your chat ID: [USER_CHAT_ID]
```

### Step 5: Test

Run the service:

```bash
npm run dev
```

Test by sending a message to your bot in Telegram. Verify:
- Bot responds
- Typing indicator appears
- No errors in logs

---

## Additional Channel Mode

Run Telegram and WhatsApp simultaneously.

### Step 1: Add Telegram Handler

Follow **Replace WhatsApp Mode → Step 1** above to add the Telegram handler.

Do NOT remove any WhatsApp code.

### Step 2: Wire Both Channels

Both handlers should call the same `processIncomingMessage` function:

```typescript
// WhatsApp handler still calls:
await processIncomingMessage({ platform: 'whatsapp', ... });

// Telegram handler calls:
await processIncomingMessage({ platform: 'telegram', ... });
```

The routing should use `chat_jid` (or similar) to store the platform and chat ID:
- WhatsApp: `whatsapp:1234567890` or just the phone number
- Telegram: `telegram:123456789` or `telegram:-987654321` for groups

### Step 3: Update Send Functions

When the agent sends a reply, route to the correct platform:

```typescript
async function sendMessage(
  chatJid: string,
  text: string
): Promise<void> {
  if (chatJid.startsWith('telegram:')) {
    const chatId = chatJid.replace('telegram:', '');
    await sendTelegramMessage(chatId, text);
  } else {
    // WhatsApp or other platform
    await sendWhatsAppMessage(chatJid, text);
  }
}
```

### Step 4: Update Memory

Update `groups/main/CLAUDE.md`:

```markdown
## Communication

You are accessed via Telegram and WhatsApp. Users can reach you on either platform.

### Telegram
- Bot username: [@your_bot_username](https://t.me/your_bot_username)
- Personal chat ID: [USER_TELEGRAM_ID]

### WhatsApp
- Phone: [USER_PHONE]
```

### Step 5: Test Both Channels

Run the service:

```bash
npm run dev
```

Test by:
1. Sending a message on WhatsApp - verify it works
2. Sending a message on Telegram - verify it works
3. Check that context is shared (if one stores state, the other sees it)

---

## Control Channel Mode

Telegram triggers actions, WhatsApp remains primary.

### Step 1: Add Minimal Telegram Handler

Add to `src/index.ts`:

```typescript
import { Telegraf } from 'telegraf';

const telegrafBot = new Telegraf(process.env.TELEGRAM_BOT_TOKEN!);

telegrafBot.on('message', async (ctx) => {
  if (!ctx.message || !('text' in ctx.message)) return;
  
  const chatId = String(ctx.chat.id);
  const content = ctx.message.text;
  
  logger.info({ chatId, content }, 'Telegram control message');
  
  try {
    // Trigger action in main group context
    // This routes Telegram input to your WhatsApp group
    const mainGroup = getRegisteredGroup('main');
    
    if (!mainGroup) {
      await telegrafBot.telegram.sendMessage(chatId, 'Agent not configured');
      return;
    }
    
    const response = await runContainerAgent(mainGroup, {
      prompt: content,
      chatJid: `telegram:${chatId}`,
      isScheduledTask: false
    });
    
    if (response.status === 'success') {
      await telegrafBot.telegram.sendMessage(chatId, response.result);
    } else {
      await telegrafBot.telegram.sendMessage(chatId, 'Error processing command');
    }
  } catch (error) {
    logger.error({ error, chatId }, 'Error in Telegram control handler');
    await telegrafBot.telegram.sendMessage(chatId, 'An error occurred');
  }
});
```

### Step 2: Start the Bot

Add bot startup (same as Replace WhatsApp mode).

### Step 3: Keep WhatsApp Running

Do NOT remove WhatsApp code. Let it continue as the primary channel.

### Step 4: Update Memory

Update `groups/main/CLAUDE.md`:

```markdown
## Communication

Primary channel: WhatsApp
Control channel: Telegram (send commands to trigger actions)

Telegram bot: [@your_bot_username](https://t.me/your_bot_username)
```

### Step 5: Test

Send a command through Telegram - it should trigger the agent and reply on Telegram.

---

## Action-Only Mode

Telegram used only for notifications.

### Step 1: Bot Token Only

Create a Telegram bot and store the token (steps from Prerequisites).

Do NOT add any message handlers. Only add the send function.

### Step 2: Add Send Function

Add to `src/index.ts`:

```typescript
import { Telegraf } from 'telegraf';

const telegrafBot = new Telegraf(process.env.TELEGRAM_BOT_TOKEN!);

async function sendTelegramMessage(chatId: string, text: string): Promise<void> {
  try {
    await telegrafBot.telegram.sendMessage(chatId, text);
    logger.info({ chatId }, 'Telegram notification sent');
  } catch (error) {
    logger.error({ error, chatId }, 'Failed to send Telegram notification');
  }
}
```

### Step 3: Trigger Notifications

When you want to send a notification (e.g., from a scheduled task):

```typescript
// In your task scheduler or notification code:
await sendTelegramMessage(
  process.env.TELEGRAM_NOTIFICATION_CHAT_ID!,
  'Task completed successfully'
);
```

### Step 4: No Need to Start Bot

Since there's no message handler, you don't need to launch the bot. Just import Telegraf and use the send function.

### Step 5: Update Memory

Update `groups/main/CLAUDE.md`:

```markdown
## Notifications

Notifications are sent to Telegram chat ID: ${TELEGRAM_NOTIFICATION_CHAT_ID}
```

---

## Group Privacy Mode (Important Gotcha)

If using Telegram groups, be aware of **privacy mode**:

**Default behavior**: Bot only sees messages mentioning it or commands (starting with `/`)

**To see all messages**: You have two options:

**Option A: Disable privacy mode (recommended for this use case)**

1. Message `@BotFather` again
2. Select your bot
3. Send `/setprivacy`
4. Select your bot
5. Choose **"Disable"**

Now the bot will see all messages in the group.

**Option B: Make bot admin**

1. Add bot to group
2. Make it an admin
3. Privacy mode is bypassed for admins

---

## Rate Limits

Telegram has rate limits to prevent abuse:

- **30 messages/second** per bot (broadcast)
- **1 message/second** per chat (in same group)
- **20 messages/minute** in groups (per user)

If you hit these limits, you'll get a `429 Too Many Requests` error. Wait a few seconds before retrying.

For notifications, batch them or add small delays:

```typescript
// Bad: Sends 100 messages instantly
for (const userId of userIds) {
  await sendTelegramMessage(userId, 'Alert');
}

// Good: Rate-limited
for (const userId of userIds) {
  await sendTelegramMessage(userId, 'Alert');
  await new Promise(r => setTimeout(r, 100)); // 100ms between messages
}
```

---

## Chat ID Formats

Telegram uses these chat ID formats:

| Type | Format | Example |
|------|--------|---------|
| Personal DM | Positive integer | `123456789` |
| Group | Negative integer | `-987654321` |
| Supergroup | Negative integer | `-1001234567890` |
| Channel | Negative integer | `-1009876543210` |

Store all chat IDs as **strings** in your database to avoid JavaScript number precision issues.

---

## Testing Procedure

### For Replace WhatsApp or Additional Channel:

1. **Start the service:**
   ```bash
   npm run dev
   ```

2. **Find your bot in Telegram:**
   - Search for your bot username (e.g., `@my_nanoclaw_bot`)
   - Or use the link: `https://t.me/your_bot_username`

3. **Send a test message:**
   ```
   hello
   ```

4. **Verify bot responds:**
   - Should see typing indicator
   - Should get a response
   - No errors in logs

5. **Test groups (if applicable):**
   - Create a test group
   - Add your bot
   - If privacy mode is on: Send `@botname hello`
   - If privacy mode is off: Send `hello`
   - Bot should respond

6. **Monitor logs:**
   ```bash
   tail -f logs/nanoclaw.log | grep -i telegram
   ```

### For Control Channel:

1. **Verify WhatsApp works first**
2. **Send a message via Telegram**
3. **Check that the main group receives input and responds back on Telegram**

### For Action-Only:

1. **Trigger a scheduled task**
2. **Verify Telegram message arrives**
3. **Check logs for send confirmation**

---

## Known Issues & Fixes

### Bot doesn't respond to messages

**Cause**: Privacy mode is on, message doesn't mention bot or start with `/`

**Fix**: 
- Add `@botname` prefix: `@my_nanoclaw_bot hello`
- Or disable privacy mode (see Group Privacy Mode section)
- Or make bot admin

### "Unauthorized" error

**Cause**: Bot token is invalid or malformed

**Fix**:
```bash
# Verify token format
echo $TELEGRAM_BOT_TOKEN
# Should be: 123456:ABC-DEF...
# Check .env file
grep TELEGRAM_BOT_TOKEN .env
```

### Bot doesn't start

**Cause**: Token is missing or invalid

**Fix**:
```bash
# Check environment variable
env | grep TELEGRAM_BOT_TOKEN

# Test token manually
curl https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe
```

### Group chat ID is not negative

**Cause**: Using the wrong ID format

**Fix**:
- For groups created after 2015: ID is negative (e.g., `-123456789`)
- For older groups: May use a different format
- Always test by getting updates: `curl https://api.telegram.org/bot${TOKEN}/getUpdates`

### Rate limit errors

**Cause**: Sending too many messages too fast

**Fix**: Add delays between messages (see Rate Limits section)

---

## Troubleshooting Commands

### Test bot token:
```bash
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | jq
```

Should return bot info if token is valid.

### Get recent messages (to find chat ID):
```bash
curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" | jq '.result[] | {chat_id: .message.chat.id, text: .message.text}'
```

### Check container logs:
```bash
cat groups/main/logs/container-*.log | tail -50
```

### Restart Telegram bot:
```bash
npm run build
npm run dev
```

---

## Removing Telegram Integration

To remove Telegram entirely:

1. **Remove from `src/index.ts`:**
   - Delete `import { Telegraf } from 'telegraf'`
   - Delete bot initialization
   - Delete message handler
   - Delete `sendTelegramMessage` and related functions
   - Delete bot startup code

2. **Remove from `.env`:**
   ```bash
   # Remove this line:
   # TELEGRAM_BOT_TOKEN="..."
   ```

3. **Remove package:**
   ```bash
   npm uninstall telegraf
   ```

4. **Update memory files:**
   - Remove Telegram section from `groups/*/CLAUDE.md`

5. **Rebuild:**
   ```bash
   npm run build
   ```

---

## Additional Resources

- [Telegraf.js Documentation](https://telegraf.js.org/)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Telegram Bot Best Practices](https://core.telegram.org/bots#bot-api)
- [BotFather Commands](https://core.telegram.org/bots#creating-a-new-bot)
