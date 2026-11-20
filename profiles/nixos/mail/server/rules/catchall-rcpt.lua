-- Score mail that only arrived because of the @domain catchall alias.
--
-- render-runtime.py writes one `@<domain> <catchall>` line per hosted domain,
-- so every localpart on every hosted domain is deliverable. Spam campaigns
-- exploit that by spraying guessed and random localparts (info, email, wkegel,
-- fvermelis, ...) at the domains instead of using a real address.
--
-- Postfix rewrites the envelope recipient to the catchall mailbox in
-- virtual_alias_maps, i.e. before the milter runs, so rspamd would otherwise
-- judge the message as ordinary mail to the canonical account. The original
-- recipient survives in the Received: "for" clause, and that is the only place
-- this signal exists.
--
-- Only localparts a real correspondent could plausibly use are exempt. A
-- message addressed to anything else has no legitimate sender, so the score is
-- additive only: it moves such mail into add_header/reject when it is also
-- otherwise suspicious, and never rejects on its own.

local rspamd_logger = require "rspamd_logger"

local PUBLISHED_LOCALPARTS = {
  chris = true,
  contact = true,
  abuse = true,
  postmaster = true,
  security = true,
}

-- rspamd exposes parsed Received headers as plain Lua tables. The envelope
-- recipient of each hop is under the "for" key (a Lua keyword, so indexed
-- rather than accessed as a field). The list is ordered newest hop first, so
-- the last hop that carries a "for" clause is the original envelope recipient
-- as presented to this MX.
local function original_rcpt_localparts(task)
  local received = task:get_received_headers()
  if type(received) ~= "table" then
    return nil
  end

  local raw = nil
  for _, hop in ipairs(received) do
    if type(hop) == "table" then
      local value = hop["for"]
      if value and value ~= "" then
        raw = value
      end
    end
  end
  if not raw then
    return nil
  end

  local localparts = {}
  for addr in raw:gmatch("<([^>]+)>") do
    local localpart = addr:match("^([^@]+)@")
    if localpart then
      localparts[#localparts + 1] = localpart:lower()
    end
  end
  if #localparts == 0 then
    local localpart = raw:match("^([^@%s<>]+)@")
    if localpart then
      localparts[1] = localpart:lower()
    end
  end
  if #localparts == 0 then
    return nil
  end

  return localparts
end

local function check(task)
  local localparts = original_rcpt_localparts(task)
  if not localparts then
    return false
  end

  -- One published recipient means a real correspondent addressed the
  -- canonical mailbox, so never score the message.
  for _, localpart in ipairs(localparts) do
    if PUBLISHED_LOCALPARTS[localpart] then
      rspamd_logger.debugx(task, "catchall_rcpt: published localpart %s", localpart)
      return false
    end
  end

  rspamd_logger.infox(
    task,
    "catchall_rcpt: unpublished catchall localpart %s",
    table.concat(localparts, ",")
  )
  return true
end

rspamd_config:register_symbol({
  name = "CATCHALL_RANDOM_RCPT",
  type = "normal",
  callback = check,
  score = 4.0,
  description = "Addressed to a catchall localpart that is not a published address",
})
