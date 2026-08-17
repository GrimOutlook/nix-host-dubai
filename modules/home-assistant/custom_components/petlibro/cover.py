"""Cover platform for PetLibro Feeders."""

from homeassistant.components.cover import (
    CoverDeviceClass,
    CoverEntity,
)
from homeassistant.core import callback
from .const import CMD_SWITCH_DOOR, DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up lid cover entities for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.append(PetLibroLidCover(coordinator, name, device_id))

    async_add_entities(entities)


class PetLibroLidCover(CoverEntity):
    """Feeder bowl lid cover entity."""

    _attr_device_class = CoverDeviceClass.DOOR

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        self.coordinator = coordinator
        self.feeder_name = feeder_name
        self.device_id = device_id
        self._attr_name = f"{feeder_name} Lid"
        self._attr_unique_id = f"{device_id}_lid"
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
    def is_closed(self) -> bool:
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("lid_state", "closed") == "closed"

    async def async_open_cover(self, **kwargs):
        """Open bowl lid."""
        payload = {"cmd": CMD_SWITCH_DOOR, "barnDoorState": 1}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)

    async def async_close_cover(self, **kwargs):
        """Close bowl lid."""
        payload = {"cmd": CMD_SWITCH_DOOR, "barnDoorState": 0}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)
