"""Number platform for PetLibro Feeders."""

from homeassistant.components.number import NumberEntity
from homeassistant.core import callback
from .const import CMD_ATTR_SET, DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up number entities for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.extend([
            PetLibroSchedulePortionsNumber(coordinator, name, device_id),
            PetLibroManualFeedPortionsNumber(coordinator, name, device_id),
            PetLibroAutoCloseTimerNumber(coordinator, name, device_id),
        ])

    async_add_entities(entities)


class PetLibroBaseNumber(NumberEntity):
    """Base class for number entities."""

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


class PetLibroSchedulePortionsNumber(PetLibroBaseNumber):
    """Quick-edit portion count for a feeder's first/primary feeding time.

    A feeder can have up to MAX_SCHEDULES_PER_FEEDER feeding times; manage
    the full list via Settings > Devices & Services > Configure.
    """

    _attr_native_min_value = 1
    _attr_native_max_value = 10
    _attr_native_step = 1
    _attr_native_unit_of_measurement = "portions"
    _attr_icon = "mdi:bowl-mix"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Schedule Portions"
        self._attr_unique_id = f"{device_id}_schedule_portions"

    @property
    def native_value(self) -> float:
        sched = self.coordinator.schedules.get(self.feeder_name, {})
        slots = sched.get("slots", [])
        return float(slots[0].get("grain_num", 1)) if slots else 1.0

    async def async_set_native_value(self, value: float):
        """Update portion count and propagate if schedule linking is enabled."""
        await self.coordinator.async_update_schedule(self.feeder_name, grain_num=int(value))


class PetLibroManualFeedPortionsNumber(PetLibroBaseNumber):
    """Number entity to select manual feed portion count."""

    _attr_native_min_value = 1
    _attr_native_max_value = 10
    _attr_native_step = 1
    _attr_native_unit_of_measurement = "portions"
    _attr_icon = "mdi:bowl-mix"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Feed Amount"
        self._attr_unique_id = f"{device_id}_feed_amount"
        self._val = 1.0

    @property
    def native_value(self) -> float:
        return self._val

    async def async_set_native_value(self, value: float):
        self._val = value
        self.async_write_ha_state()


class PetLibroAutoCloseTimerNumber(PetLibroBaseNumber):
    """Number entity for auto-close timer setting."""

    _attr_native_min_value = 0
    _attr_native_max_value = 120
    _attr_native_step = 1
    _attr_native_unit_of_measurement = "s"
    _attr_icon = "mdi:timer-outline"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Auto-Close Timer"
        self._attr_unique_id = f"{device_id}_close_door_time"
        self._val = 30.0

    @property
    def native_value(self) -> float:
        return self._val

    async def async_set_native_value(self, value: float):
        self._val = value
        payload = {"cmd": CMD_ATTR_SET, "closeDoorTimeSec": int(value)}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)
        self.async_write_ha_state()
