"""Data Coordinator for PetLibro Feeders."""

from datetime import datetime
import json
import logging
import time

from homeassistant.components import mqtt
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store

from .const import (
    CMD_ADD_OR_UPDATE_RFID,
    CMD_DEL_RFID,
    CMD_FEEDING_PLAN,
    CMD_MANUAL_FEEDING,
    CMD_SWITCH_DOOR,
    CMD_UNBIND_PET,
    DOMAIN,
    STORAGE_KEY_PETS,
    STORAGE_KEY_SCHEDULES,
    STORAGE_VERSION,
    TOPIC_EVENT_POST_PATTERN,
    TOPIC_HEART_POST_PATTERN,
    TOPIC_SERVICE_POST_PATTERN,
    TOPIC_SUB_PATTERN,
)

_LOGGER = logging.getLogger(__name__)


class PetLibroCoordinator:
    """Central manager for PetLibro feeders, pet profile mapping, and schedule syncing."""

    def __init__(self, hass: HomeAssistant, feeders: list[dict]):
        self.hass = hass
        self.feeders = feeders  # list of {"name": ..., "device_id": ...}
        self.feeder_map = {f["name"]: f["device_id"] for f in feeders}
        self.device_id_map = {f["device_id"]: f["name"] for f in feeders}

        self._pet_store = Store(hass, STORAGE_VERSION, STORAGE_KEY_PETS)
        self._schedule_store = Store(hass, STORAGE_VERSION, STORAGE_KEY_SCHEDULES)

        # Pet registry: { collar_tag_hex: {"pet_name": str, "collar_tag": str, "feeder_id": str} }
        self.pets: dict[str, dict] = {}

        # Schedules: { feeder_name: {"time": "08:30", "grain_num": 1, "repeat_day": "1111111", "enabled": True, "linked": True} }
        self.schedules: dict[str, dict] = {}

        # Runtime live state per feeder_name
        self.feeder_states: dict[str, dict] = {}
        for f in feeders:
            name = f["name"]
            self.feeder_states[name] = {
                "online": False,
                "last_heartbeat": 0,
                "rssi": None,
                "lid_state": "closed",
                "feed_jam": False,
                "last_fed": None,
                "last_scanned_tag": None,
                "last_scanned_pet": None,
                "bowl_activity": None,
                "last_error": None,
                "last_boot": None,
                "last_service_response": None,
            }

        self._listeners = []
        self._unsubscribe_mqtt = []

    async def async_setup(self):
        """Load stored pet and schedule configurations and subscribe to MQTT topics."""
        # Load pet mapping storage
        pet_data = await self._pet_store.async_load()
        if pet_data and isinstance(pet_data, dict):
            self.pets = pet_data.get("pets", {})

        # Load schedule storage
        schedule_data = await self._schedule_store.async_load()
        if schedule_data and isinstance(schedule_data, dict):
            self.schedules = schedule_data.get("schedules", {})

        # Initialize default schedule for any feeder missing from storage
        for f in self.feeders:
            name = f["name"]
            if name not in self.schedules:
                self.schedules[name] = {
                    "time": "08:00",
                    "grain_num": 1,
                    "repeat_day": "1111111",
                    "enabled": True,
                    "linked": True,
                }

        # Subscribe to MQTT topics for each feeder
        for f in self.feeders:
            device_id = f["device_id"]
            name = f["name"]

            # Heartbeat topic
            topic_heart = TOPIC_HEART_POST_PATTERN.format(device_id=device_id)
            unsub1 = await mqtt.async_subscribe(
                self.hass, topic_heart, self._make_mqtt_callback(name, "heart")
            )
            self._unsubscribe_mqtt.append(unsub1)

            # Event post topic
            topic_event = TOPIC_EVENT_POST_PATTERN.format(device_id=device_id)
            unsub2 = await mqtt.async_subscribe(
                self.hass, topic_event, self._make_mqtt_callback(name, "event")
            )
            self._unsubscribe_mqtt.append(unsub2)

            # Service post topic
            topic_service = TOPIC_SERVICE_POST_PATTERN.format(device_id=device_id)
            unsub3 = await mqtt.async_subscribe(
                self.hass, topic_service, self._make_mqtt_callback(name, "service")
            )
            self._unsubscribe_mqtt.append(unsub3)

        _LOGGER.info("PetLibro coordinator initialized for %d feeders", len(self.feeders))

    def _make_mqtt_callback(self, feeder_name: str, topic_kind: str):
        @callback
        def handle_message(msg):
            try:
                payload = json.loads(msg.payload)
            except (json.JSONDecodeError, TypeError):
                return
            self._process_mqtt_message(feeder_name, topic_kind, payload)

        return handle_message

    def _process_mqtt_message(self, feeder_name: str, topic_kind: str, payload: dict):
        """Process incoming device events and heartbeats."""
        state = self.feeder_states[feeder_name]
        now_iso = datetime.now().isoformat()
        cmd = payload.get("cmd")

        if topic_kind == "heart":
            if cmd == "HEARTBEAT":
                state["online"] = True
                state["last_heartbeat"] = time.time()
                state["rssi"] = payload.get("rssi")

        elif topic_kind == "event":
            if cmd == "GRAIN_OUTPUT_EVENT":
                exec_step = payload.get("execStep")
                finished = payload.get("finished", False)
                if exec_step in ["GRAIN_BLOCKING", "GRAIN_BLOCKED", "GRAIN_STUCK"]:
                    state["feed_jam"] = True
                elif exec_step == "GRAIN_END" or finished:
                    state["feed_jam"] = False
                    state["last_fed"] = now_iso

            elif cmd == "WAREHOUSE_DOOR_EVENT":
                trigger_type = payload.get("triggerType")
                if trigger_type == "COVER_OPEN":
                    state["lid_state"] = "open"
                elif trigger_type == "COVER_CLOSE":
                    state["lid_state"] = "closed"

            elif cmd == "PET_IDENTIFY_EVENT":
                tag = payload.get("calibrationTag", "")
                member_id = payload.get("memberId", "")
                state["last_scanned_tag"] = tag
                
                # Match tag or member_id against registered pet names
                pet_name = self.get_pet_name_for_tag(tag) or member_id or tag
                state["last_scanned_pet"] = pet_name

            elif cmd == "MACHINE_INFRARED_EVENT":
                state["bowl_activity"] = now_iso

            elif cmd == "ERROR_EVENT":
                state["last_error"] = payload.get("errorMsg", "Unknown Error")

            elif cmd == "DEVICE_START_EVENT":
                state["last_boot"] = now_iso

        elif topic_kind == "service":
            state["last_service_response"] = payload.get("code", 0)

        self._notify_listeners()

    def get_pet_name_for_tag(self, tag_hex: str) -> str | None:
        """Find assigned pet name for an RFID calibration tag."""
        if not tag_hex:
            return None
        pet_entry = self.pets.get(tag_hex.upper())
        if pet_entry:
            return pet_entry.get("pet_name")
        # Secondary check by member_id
        for entry in self.pets.values():
            if entry.get("collar_tag", "").upper() == tag_hex.upper():
                return entry.get("pet_name")
        return None

    async def async_assign_collar(self, feeder_name: str, pet_name: str, collar_tag: str):
        """Assign collar tag to pet and update target feeder over MQTT."""
        device_id = self.feeder_map.get(feeder_name)
        if not device_id:
            _LOGGER.error("Feeder %s not found", feeder_name)
            return

        tag_clean = collar_tag.strip().upper()
        pet_clean = pet_name.strip()

        # Update data store
        self.pets[tag_clean] = {
            "pet_name": pet_clean,
            "collar_tag": tag_clean,
            "feeder_id": feeder_name,
            "member_id": pet_clean.lower().replace(" ", "_"),
        }
        await self._pet_store.async_save({"pets": self.pets})

        # Send ADD_OR_UPDATE_RFID_SERVICE command to feeder hardware
        cmd_payload = {
            "cmd": CMD_ADD_OR_UPDATE_RFID,
            "memberId": pet_clean.lower().replace(" ", "_"),
            "calibrationTag": tag_clean,
        }
        await self.async_publish_cmd(feeder_name, cmd_payload)
        _LOGGER.info("Assigned collar %s (%s) to feeder %s", tag_clean, pet_clean, feeder_name)
        self._notify_listeners()

    async def async_delete_collar(self, feeder_name: str, collar_tag: str):
        """Remove a pet collar registration from a feeder."""
        device_id = self.feeder_map.get(feeder_name)
        tag_clean = collar_tag.strip().upper()

        member_id = None
        if tag_clean in self.pets:
            member_id = self.pets[tag_clean].get("member_id")
            del self.pets[tag_clean]
            await self._pet_store.async_save({"pets": self.pets})

        if member_id and device_id:
            cmd_payload = {
                "cmd": CMD_DEL_RFID,
                "memberId": member_id,
            }
            await self.async_publish_cmd(feeder_name, cmd_payload)
        self._notify_listeners()

    async def async_update_schedule(
        self,
        feeder_name: str,
        time_str: str | None = None,
        grain_num: int | None = None,
        repeat_day: str | None = None,
        enabled: bool | None = None,
        linked: bool | None = None,
    ):
        """Update feeder schedule parameters and propagate to linked feeders if linked is True."""
        if feeder_name not in self.schedules:
            self.schedules[feeder_name] = {
                "time": "08:00",
                "grain_num": 1,
                "repeat_day": "1111111",
                "enabled": True,
                "linked": True,
            }

        sched = self.schedules[feeder_name]
        if time_str is not None:
            sched["time"] = time_str
        if grain_num is not None:
            sched["grain_num"] = grain_num
        if repeat_day is not None:
            sched["repeat_day"] = repeat_day
        if enabled is not None:
            sched["enabled"] = enabled
        if linked is not None:
            sched["linked"] = linked

        target_feeders = [feeder_name]

        # If schedule linking is enabled for this feeder, propagate schedule settings to all other linked feeders!
        if sched.get("linked", True):
            for other_name, other_sched in self.schedules.items():
                if other_name != feeder_name and other_sched.get("linked", True):
                    if time_str is not None:
                        other_sched["time"] = time_str
                    if grain_num is not None:
                        other_sched["grain_num"] = grain_num
                    if repeat_day is not None:
                        other_sched["repeat_day"] = repeat_day
                    target_feeders.append(other_name)

        await self._schedule_store.async_save({"schedules": self.schedules})

        # Send updated MQTT feeding plan to all target feeders
        for f_name in target_feeders:
            await self.async_send_feeding_plan_mqtt(f_name)

        self._notify_listeners()

    async def async_toggle_schedule_enabled(self, feeder_name: str, enabled: bool):
        """Enable or disable schedule dispensing for a feeder."""
        await self.async_update_schedule(feeder_name, enabled=enabled)

    async def async_send_feeding_plan_mqtt(self, feeder_name: str):
        """Dispatch DEVICE_FEEDING_PLAN_SERVICE over MQTT for a feeder."""
        sched = self.schedules.get(feeder_name, {})
        is_enabled = sched.get("enabled", True)

        # Native protocol disabling via skipEndTime (Option 1):
        # When enabled: skipEndTime = 0 (plan executes normally).
        # When disabled: skipEndTime = 2147483647 (plan paused until far-future timestamp).
        skip_end_time = 0 if is_enabled else 2147483647

        cmd_payload = {
            "cmd": CMD_FEEDING_PLAN,
            "channelPlanNum": 1,
            "planId": "ha_plan",
            "grainNum": sched.get("grain_num", 1),
            "executionTime": sched.get("time", "08:00"),
            "repeatDay": sched.get("repeat_day", "1111111"),
            "audioTimes": 2,
            "syncTime": int(time.time()),
            "skipEndTime": skip_end_time,
        }
        await self.async_publish_cmd(feeder_name, cmd_payload)

    async def async_manual_feed(self, feeder_name: str, grain_num: int):
        """Dispense food immediately via MANUAL_FEEDING_SERVICE."""
        cmd_payload = {
            "cmd": CMD_MANUAL_FEEDING,
            "grainNum": max(1, int(grain_num)),
        }
        await self.async_publish_cmd(feeder_name, cmd_payload)

    async def async_publish_cmd(self, feeder_name: str, payload: dict):
        """Publish JSON payload to feeder's MQTT sub topic."""
        device_id = self.feeder_map.get(feeder_name)
        if not device_id:
            _LOGGER.error("Cannot publish: Feeder %s unknown", feeder_name)
            return

        topic = TOPIC_SUB_PATTERN.format(device_id=device_id)
        payload_str = json.dumps(payload)
        await mqtt.async_publish(self.hass, topic, payload_str)
        _LOGGER.debug("Published to %s: %s", topic, payload_str)

    def add_listener(self, update_callback):
        self._listeners.append(update_callback)

    def remove_listener(self, update_callback):
        if update_callback in self._listeners:
            self._listeners.remove(update_callback)

    def _notify_listeners(self):
        for callback_fn in self._listeners:
            callback_fn()
