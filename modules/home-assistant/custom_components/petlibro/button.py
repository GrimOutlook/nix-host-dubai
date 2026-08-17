"""Button platform for PetLibro Feeders."""

from homeassistant.components.button import ButtonEntity
from homeassistant.core import callback
from homeassistant.helpers.entity import EntityCategory
from .const import (
    CMD_ATTR_GET,
    CMD_DEVICE_PROPERTIES,
    CMD_DISCOVERY_RFID,
    CMD_DISCOVERY_STOP,
    DOMAIN,
)


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up button entities for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.extend([
            PetLibroFeedNowButton(coordinator, name, device_id),
            PetLibroApplyScheduleButton(coordinator, name, device_id),
            PetLibroSyncScheduleButton(coordinator, name, device_id),
            PetLibroRefreshSettingsButton(coordinator, name, device_id),
            PetLibroRefreshDeviceInfoButton(coordinator, name, device_id),
            PetLibroStartRFIDDiscoveryButton(coordinator, name, device_id),
            PetLibroStopRFIDDiscoveryButton(coordinator, name, device_id),
        ])

    async_add_entities(entities)


class PetLibroBaseButton(ButtonEntity):
    """Base button entity."""

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        self.coordinator = coordinator
        self.feeder_name = feeder_name
        self.device_id = device_id
        self._attr_device_info = {
            "identifiers": {(DOMAIN, f"plaf301_{device_id}")},
            "name": feeder_name,
            "manufacturer": "PETLIBRO",
            "model": "PLAF301",
        }

    async def async_added_to_hass(self):
        self.coordinator.add_listener(self._handle_coordinator_update)

    async def async_will_remove_from_hass(self):
        self.coordinator.remove_listener(self._handle_coordinator_update)

    @callback
    def _handle_coordinator_update(self):
        self.async_write_ha_state()


class PetLibroFeedNowButton(PetLibroBaseButton):
    """Feed now button."""

    _attr_icon = "mdi:bowl-mix"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Feed Now"
        self._attr_unique_id = f"{device_id}_feed_now"

    async def async_press(self):
        # Look up manual feed amount entity or default to 1 portion
        entity_id = f"number.{self.feeder_name.replace('-', '_')}_feed_amount"
        portions = 1
        state_obj = self.hass.states.get(entity_id)
        if state_obj and state_obj.state.isdigit():
            portions = int(state_obj.state)
        await self.coordinator.async_manual_feed(self.feeder_name, portions)


class PetLibroApplyScheduleButton(PetLibroBaseButton):
    """Apply schedule button."""

    _attr_icon = "mdi:calendar-clock"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Apply Schedule"
        self._attr_unique_id = f"{device_id}_apply_schedule"

    async def async_press(self):
        await self.coordinator.async_send_feeding_plan_mqtt(self.feeder_name)


class PetLibroSyncScheduleButton(PetLibroBaseButton):
    """Sync schedule across all linked feeders button."""

    _attr_icon = "mdi:sync"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Sync Schedule to Linked Feeders"
        self._attr_unique_id = f"{device_id}_sync_schedule"

    async def async_press(self):
        sched = self.coordinator.schedules.get(self.feeder_name, {})
        await self.coordinator.async_update_schedule(
            self.feeder_name,
            time_str=sched.get("time"),
            grain_num=sched.get("grain_num"),
            repeat_day=sched.get("repeat_day"),
            linked=True,
        )


class PetLibroRefreshSettingsButton(PetLibroBaseButton):
    """Refresh settings button."""

    _attr_icon = "mdi:refresh"
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Refresh Settings"
        self._attr_unique_id = f"{device_id}_attr_get"

    async def async_press(self):
        await self.coordinator.async_publish_cmd(self.feeder_name, {"cmd": CMD_ATTR_GET})


class PetLibroRefreshDeviceInfoButton(PetLibroBaseButton):
    """Refresh device info button."""

    _attr_icon = "mdi:information-outline"
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Refresh Device Info"
        self._attr_unique_id = f"{device_id}_device_properties"

    async def async_press(self):
        await self.coordinator.async_publish_cmd(self.feeder_name, {"cmd": CMD_DEVICE_PROPERTIES})


class PetLibroStartRFIDDiscoveryButton(PetLibroBaseButton):
    """Start RFID scan discovery mode button."""

    _attr_icon = "mdi:card-search"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Start RFID Discovery"
        self._attr_unique_id = f"{device_id}_rfid_discovery_start"

    async def async_press(self):
        await self.coordinator.async_publish_cmd(self.feeder_name, {"cmd": CMD_DISCOVERY_RFID})


class PetLibroStopRFIDDiscoveryButton(PetLibroBaseButton):
    """Stop RFID scan discovery mode button."""

    _attr_icon = "mdi:card-search-outline"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Stop RFID Discovery"
        self._attr_unique_id = f"{device_id}_rfid_discovery_stop"

    async def async_press(self):
        await self.coordinator.async_publish_cmd(self.feeder_name, {"cmd": CMD_DISCOVERY_STOP})
