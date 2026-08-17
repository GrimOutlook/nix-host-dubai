"""Switch platform for PetLibro Feeders."""

from homeassistant.components.switch import SwitchEntity
from homeassistant.core import callback
from homeassistant.helpers.entity import EntityCategory
from .const import CMD_ATTR_SET, DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up switches for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.extend([
            PetLibroScheduleEnabledSwitch(coordinator, name, device_id),
            PetLibroScheduleLinkedSwitch(coordinator, name, device_id),
            PetLibroAttrSwitch(coordinator, name, device_id, "Child Lock", "child_lock", "childLockSwitch", "mdi:lock"),
            PetLibroAttrSwitch(coordinator, name, device_id, "Sound", "sound", "soundSwitch", "mdi:volume-high"),
            PetLibroAttrSwitch(coordinator, name, device_id, "Disable Physical Buttons", "disable_buttons", "disableHardwareButton", "mdi:gesture-tap-button"),
            PetLibroAttrSwitch(coordinator, name, device_id, "Screen Display", "screen_display", "enableScreenDisplay", "mdi:monitor"),
        ])

    async_add_entities(entities)


class PetLibroBaseSwitch(SwitchEntity):
    """Base switch entity."""

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


class PetLibroScheduleEnabledSwitch(PetLibroBaseSwitch):
    """Switch to enable or pause/disable scheduled feeding dispensing."""

    _attr_icon = "mdi:clock-check"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Schedule Enabled"
        self._attr_unique_id = f"{device_id}_schedule_enabled"

    @property
    def is_on(self) -> bool:
        sched = self.coordinator.schedules.get(self.feeder_name, {})
        return sched.get("enabled", True)

    async def async_turn_on(self, **kwargs):
        """Enable feeding schedule."""
        await self.coordinator.async_toggle_schedule_enabled(self.feeder_name, True)

    async def async_turn_off(self, **kwargs):
        """Disable/pause feeding schedule."""
        await self.coordinator.async_toggle_schedule_enabled(self.feeder_name, False)


class PetLibroScheduleLinkedSwitch(PetLibroBaseSwitch):
    """Switch to link or unlink feeder schedule propagation."""

    _attr_icon = "mdi:link-variant"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Link Schedule"
        self._attr_unique_id = f"{device_id}_schedule_linked"

    @property
    def is_on(self) -> bool:
        sched = self.coordinator.schedules.get(self.feeder_name, {})
        return sched.get("linked", True)

    async def async_turn_on(self, **kwargs):
        """Enable schedule linking for this feeder."""
        await self.coordinator.async_update_schedule(self.feeder_name, linked=True)

    async def async_turn_off(self, **kwargs):
        """Disable schedule linking for this feeder."""
        await self.coordinator.async_update_schedule(self.feeder_name, linked=False)


class PetLibroAttrSwitch(PetLibroBaseSwitch):
    """Switch entity for hardware ATTR_SET_SERVICE settings."""

    def __init__(self, coordinator, feeder_name: str, device_id: str, label: str, key: str, field_name: str, icon: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} {label}"
        self._attr_unique_id = f"{device_id}_{key}"
        self._attr_icon = icon
        self.field_name = field_name
        self._is_on = False

    @property
    def is_on(self) -> bool:
        return self._is_on

    async def async_turn_on(self, **kwargs):
        self._is_on = True
        payload = {"cmd": CMD_ATTR_SET, self.field_name: 1}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)
        self.async_write_ha_state()

    async def async_turn_off(self, **kwargs):
        self._is_on = False
        payload = {"cmd": CMD_ATTR_SET, self.field_name: 0}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)
        self.async_write_ha_state()
