"""The PetLibro Feeder integration."""

import logging
import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.helpers import config_validation as cv

from .const import (
    DEFAULT_FEEDERS,
    DOMAIN,
    MAX_SCHEDULES_PER_FEEDER,
    SERVICE_ADD_SCHEDULE,
    SERVICE_ASSIGN_COLLAR,
    SERVICE_DELETE_SCHEDULE,
    SERVICE_FEED,
    SERVICE_SET_SCHEDULE,
    SERVICE_SET_SCHEDULE_ENABLED,
    SERVICE_SYNC_SCHEDULES,
)
from .coordinator import PetLibroCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [
    "binary_sensor",
    "sensor",
    "cover",
    "switch",
    "number",
    "select",
    "button",
    "time",
    "text",
]


async def async_setup(hass: HomeAssistant, config: dict):
    """Set up PetLibro integration from YAML if present."""
    return True


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry):
    """Set up PetLibro Feeder from a config entry."""
    feeders = entry.data.get("feeders", DEFAULT_FEEDERS)

    coordinator = PetLibroCoordinator(hass, feeders)
    await coordinator.async_setup()

    hass.data.setdefault(DOMAIN, {})
    hass.data[DOMAIN][entry.entry_id] = coordinator

    # Register custom HA services
    async def handle_feed(call: ServiceCall):
        feeder_id = call.data["feeder"]
        portions = call.data.get("portions", 1)
        await coordinator.async_manual_feed(feeder_id, portions)

    async def handle_assign_collar(call: ServiceCall):
        feeder_id = call.data["feeder"]
        pet_name = call.data["pet_name"]
        collar_tag = call.data["collar_tag"]
        await coordinator.async_assign_collar(feeder_id, pet_name, collar_tag)

    async def handle_set_schedule(call: ServiceCall):
        """Update a feeder's Nth feeding time (slot 0 = the first/primary one)."""
        feeder_id = call.data["feeder"]
        time_str = call.data.get("time")
        portions = call.data.get("portions")
        repeat_day = call.data.get("repeat_day")
        enabled = call.data.get("enabled")
        linked = call.data.get("linked")
        slot = call.data.get("slot", 0)
        if linked is not None:
            await coordinator.async_set_schedule_linked(feeder_id, linked)
        if any(v is not None for v in (time_str, portions, repeat_day, enabled)):
            await coordinator.async_update_schedule(
                feeder_id,
                time_str=time_str,
                grain_num=portions,
                repeat_day=repeat_day,
                enabled=enabled,
                slot_index=slot,
            )

    async def handle_add_schedule(call: ServiceCall):
        """Add a new feeding time to a feeder."""
        feeder_id = call.data["feeder"]
        await coordinator.async_add_schedule_slot(
            feeder_id,
            time_str=call.data.get("time", "08:00"),
            grain_num=call.data.get("portions", 1),
            repeat_day=call.data.get("repeat_day", "1111111"),
            enabled=call.data.get("enabled", True),
        )

    async def handle_delete_schedule(call: ServiceCall):
        """Remove a feeding time from a feeder by its position in the list."""
        feeder_id = call.data["feeder"]
        slot = call.data["slot"]
        slots = coordinator.schedules.get(feeder_id, {}).get("slots", [])
        if 0 <= slot < len(slots):
            await coordinator.async_delete_schedule_slot(feeder_id, slots[slot]["id"])

    async def handle_sync_schedules(call: ServiceCall):
        source_feeder = call.data["source_feeder"]
        await coordinator.async_sync_schedule_to_linked(source_feeder)

    async def handle_set_schedule_enabled(call: ServiceCall):
        feeder_id = call.data["feeder"]
        enabled = call.data["enabled"]
        await coordinator.async_toggle_schedule_enabled(feeder_id, enabled)

    hass.services.async_register(
        DOMAIN,
        SERVICE_FEED,
        handle_feed,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Optional("portions", default=1): cv.positive_int,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_ASSIGN_COLLAR,
        handle_assign_collar,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Required("pet_name"): cv.string,
            vol.Required("collar_tag"): cv.string,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SET_SCHEDULE,
        handle_set_schedule,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Optional("slot", default=0): vol.All(vol.Coerce(int), vol.Range(min=0, max=MAX_SCHEDULES_PER_FEEDER - 1)),
            vol.Optional("time"): cv.string,
            vol.Optional("portions"): cv.positive_int,
            vol.Optional("repeat_day"): cv.string,
            vol.Optional("enabled"): cv.boolean,
            vol.Optional("linked"): cv.boolean,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_ADD_SCHEDULE,
        handle_add_schedule,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Optional("time", default="08:00"): cv.string,
            vol.Optional("portions", default=1): cv.positive_int,
            vol.Optional("repeat_day", default="1111111"): cv.string,
            vol.Optional("enabled", default=True): cv.boolean,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_DELETE_SCHEDULE,
        handle_delete_schedule,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Required("slot"): vol.All(vol.Coerce(int), vol.Range(min=0, max=MAX_SCHEDULES_PER_FEEDER - 1)),
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SYNC_SCHEDULES,
        handle_sync_schedules,
        schema=vol.Schema({
            vol.Required("source_feeder"): cv.string,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SET_SCHEDULE_ENABLED,
        handle_set_schedule_enabled,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Required("enabled"): cv.boolean,
        }),
    )

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry):
    """Unload a config entry."""
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unload_ok
