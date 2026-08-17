"""Time platform for PetLibro Feeders."""

from datetime import time as dt_time
from homeassistant.components.time import TimeEntity
from homeassistant.core import callback
from .const import DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up time entities for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.append(PetLibroScheduleTime(coordinator, name, device_id))

    async_add_entities(entities)


class PetLibroScheduleTime(TimeEntity):
    """Quick-edit time entity for a feeder's first/primary feeding time.

    A feeder can have up to MAX_SCHEDULES_PER_FEEDER feeding times; manage
    the full list via Settings > Devices & Services > Configure.
    """

    _attr_icon = "mdi:clock-outline"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        self.coordinator = coordinator
        self.feeder_name = feeder_name
        self.device_id = device_id
        self._attr_name = f"{feeder_name} Schedule Time"
        self._attr_unique_id = f"{device_id}_schedule_time"
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

    @property
    def native_value(self) -> dt_time | None:
        sched = self.coordinator.schedules.get(self.feeder_name, {})
        slots = sched.get("slots", [])
        time_str = slots[0].get("time", "08:00") if slots else "08:00"
        try:
            parts = time_str.split(":")
            return dt_time(int(parts[0]), int(parts[1]))
        except (ValueError, IndexError):
            return dt_time(8, 0)

    async def async_set_value(self, value: dt_time) -> None:
        """Set schedule time and propagate if schedule linking is enabled."""
        time_str = value.strftime("%H:%M")
        await self.coordinator.async_update_schedule(self.feeder_name, time_str=time_str)
