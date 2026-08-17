"""Config flow and Options flow for PetLibro Feeder integration."""

import logging
import voluptuous as vol

from homeassistant import config_entries
from homeassistant.core import callback

from .const import DEFAULT_FEEDERS, DOMAIN

_LOGGER = logging.getLogger(__name__)


class PetLibroConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Handle a config flow for PetLibro Feeder."""

    VERSION = 1

    async def async_step_user(self, user_input=None):
        """Handle initial step."""
        if self._async_current_entries():
            return self.async_abort(reason="already_configured")

        if user_input is not None:
            return self.async_create_entry(title="PetLibro Feeders", data={"feeders": DEFAULT_FEEDERS})

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({}),
            description_placeholders={"info": "Click Submit to initialize PetLibro feeders."},
        )

    @staticmethod
    @callback
    def async_get_options_flow(config_entry):
        """Get the options flow for this handler."""
        return PetLibroOptionsFlowHandler(config_entry)


class PetLibroOptionsFlowHandler(config_entries.OptionsFlow):
    """Handle PetLibro options sub-menu flow (Settings > Devices & Services > Configure)."""

    def __init__(self, config_entry: config_entries.ConfigEntry):
        self.config_entry = config_entry
        self._selected_action = None
        self._selected_feeder = None

    async def async_step_init(self, user_input=None):
        """Display sub-menu options for managing feeders, schedules, and collars."""
        return self.async_show_menu(
            step_id="init",
            menu_options=[
                "schedule_config",
                "assign_collar",
                "delete_collar",
            ],
        )

    async def async_step_schedule_config(self, user_input=None):
        """Configure schedule settings for a selected feeder."""
        coordinator = self.hass.data[DOMAIN][self.config_entry.entry_id]
        feeder_names = [f["name"] for f in coordinator.feeders]

        if user_input is not None:
            feeder_name = user_input["feeder"]
            await coordinator.async_update_schedule(
                feeder_name,
                time_str=user_input.get("time"),
                grain_num=user_input.get("portions"),
                repeat_day=user_input.get("repeat_day"),
                enabled=user_input.get("enabled"),
                linked=user_input.get("linked"),
            )
            return self.async_create_entry(title="", data={})

        default_feeder = feeder_names[0] if feeder_names else ""
        current_sched = coordinator.schedules.get(default_feeder, {})

        data_schema = vol.Schema({
            vol.Required("feeder", default=default_feeder): vol.In(feeder_names),
            vol.Optional("time", default=current_sched.get("time", "08:00")): str,
            vol.Optional("portions", default=current_sched.get("grain_num", 1)): vol.All(vol.Coerce(int), vol.Range(min=1, max=10)),
            vol.Optional("repeat_day", default=current_sched.get("repeat_day", "1111111")): str,
            vol.Optional("enabled", default=current_sched.get("enabled", True)): bool,
            vol.Optional("linked", default=current_sched.get("linked", True)): bool,
        })

        return self.async_show_form(
            step_id="schedule_config",
            data_schema=data_schema,
        )

    async def async_step_assign_collar(self, user_input=None):
        """Assign pet name and collar RFID tag to a feeder."""
        coordinator = self.hass.data[DOMAIN][self.config_entry.entry_id]
        feeder_names = [f["name"] for f in coordinator.feeders]

        if user_input is not None:
            await coordinator.async_assign_collar(
                feeder_name=user_input["feeder"],
                pet_name=user_input["pet_name"],
                collar_tag=user_input["collar_tag"],
            )
            return self.async_create_entry(title="", data={})

        data_schema = vol.Schema({
            vol.Required("feeder", default=feeder_names[0] if feeder_names else ""): vol.In(feeder_names),
            vol.Required("pet_name"): str,
            vol.Required("collar_tag"): str,
        })

        return self.async_show_form(
            step_id="assign_collar",
            data_schema=data_schema,
        )

    async def async_step_delete_collar(self, user_input=None):
        """Remove a registered pet collar tag."""
        coordinator = self.hass.data[DOMAIN][self.config_entry.entry_id]
        feeder_names = [f["name"] for f in coordinator.feeders]

        if user_input is not None:
            await coordinator.async_delete_collar(
                feeder_name=user_input["feeder"],
                collar_tag=user_input["collar_tag"],
            )
            return self.async_create_entry(title="", data={})

        data_schema = vol.Schema({
            vol.Required("feeder", default=feeder_names[0] if feeder_names else ""): vol.In(feeder_names),
            vol.Required("collar_tag"): str,
        })

        return self.async_show_form(
            step_id="delete_collar",
            data_schema=data_schema,
        )
