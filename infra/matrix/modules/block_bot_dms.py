"""
Synapse spam-checker module to block DMs to the WhatsApp bridge bot.

Blocks:
- Invites to the bot from non-admin users.
- Creating DM rooms targeting the bot by non-admin users.
- Sending messages in an existing 1:1 room with the bot (belt-and-suspenders).

Configure in Synapse (see modules.yaml mounted via conf.d):

modules:
  - module: block_bot_dms.BlockBotDMs
    config:
      bot_mxid: "@whatsappbot:messie.localhost"
      admins:
        - "@bridge-admin:messie.localhost"
"""

from typing import Any, Dict, Optional, Set
import logging

from synapse.module_api import ModuleApi, NOT_SPAM


class BlockBotDMs:
    def __init__(self, config: Dict[str, Any], api: ModuleApi):
        self.api = api
        self.log = logging.getLogger(__name__)
        self.bot_mxid: str = config.get("bot_mxid") or "@whatsappbot:messie.localhost"
        self.admins: Set[str] = set(config.get("admins", []))
        # Behavior toggles
        self.block_dm_invites: bool = bool(config.get("block_dm_invites", False))
        self.require_prefix_in_dm: bool = bool(config.get("require_prefix_in_dm", False))
        self.prefix: str = str(config.get("prefix", "!wa"))

        api.register_spam_checker_callbacks(
            user_may_invite=self.user_may_invite,
            user_may_create_room=self.user_may_create_room,
            check_event_for_spam=self.check_event_for_spam,
        )
        self.log.info(
            "BlockBotDMs loaded: bot=%s admins=%s block_dm_invites=%s require_prefix_in_dm=%s prefix=%s",
            self.bot_mxid,
            sorted(self.admins),
            self.block_dm_invites,
            self.require_prefix_in_dm,
            self.prefix,
        )

    async def user_may_invite(self, inviter: str, invitee: str, room_id: str):
        # Optionally block inviting the bot when this would create a 1:1 DM
        if invitee == self.bot_mxid and inviter not in self.admins and self.block_dm_invites:
            try:
                members = await self._joined_members_in_room(room_id)
                self.log.debug("invite check room=%s inviter=%s invitee=%s members=%s", room_id, inviter, invitee, list(members))
                if len(members) <= 1 and inviter in members:
                    return "Inviting the bridge bot to DMs is disabled"
            except Exception:
                pass
        return NOT_SPAM

    async def user_may_create_room(self, user_id: str, room_config: Dict[str, Any]):
        # Optionally block creation of a DM targeting the bot
        if self.block_dm_invites:
            is_dm = bool(room_config.get("is_direct"))
            invited: Set[str] = set(room_config.get("invite", []) or [])
            self.log.debug("create_room check user=%s is_dm=%s invited=%s", user_id, is_dm, list(invited))
            if is_dm and self.bot_mxid in invited and user_id not in self.admins:
                return "Direct messages to the bridge bot are disabled"
        return NOT_SPAM

    async def check_event_for_spam(self, event, spamcheck_context: Optional[Any] = None):
        # In a 1:1 DM with the bot, either block completely or enforce prefix
        try:
            etype = getattr(event, "type", None)
            if etype in ("m.room.message", "m.room.encrypted"):
                members = await self._joined_members_in_room(event.room_id)
                self.log.debug("event check type=%s room=%s sender=%s members=%s", etype, event.room_id, getattr(event, "sender", ""), list(members))
                if len(members) == 2 and self.bot_mxid in members and event.sender not in self.admins:
                    if self.block_dm_invites:
                        return "Direct messages to the bridge bot are disabled"
                    if self.require_prefix_in_dm:
                        body = None
                        try:
                            body = event.content.get("body")  # type: ignore[attr-defined]
                        except Exception:
                            body = None
                        if not (isinstance(body, str) and body.startswith(self.prefix)):
                            return f"DMs to the bridge bot require commands starting with '{self.prefix}'"
        except Exception:
            # Fail open to avoid blocking legitimate traffic if state lookup fails
            pass
        return NOT_SPAM

    async def _joined_members_in_room(self, room_id: str) -> Set[str]:
        # Query full room state and filter for joined members to be compatible across Synapse versions
        state = await self.api.get_room_state(room_id)
        users: Set[str] = set()
        for ev in state:
            if ev.get("type") == "m.room.member" and ev.get("content", {}).get("membership") == "join":
                if ev.get("state_key"):
                    users.add(ev["state_key"])
        return users


def load_module(config: Dict[str, Any], api: ModuleApi):
    return BlockBotDMs(config, api)
