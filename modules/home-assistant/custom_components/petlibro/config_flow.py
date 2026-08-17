"""Config flow and Options flow for PetLibro Feeder integration."""

import logging
import voluptuous as vol

from homeassistant import config_entries
from homeassistant.core import callback

from .const import DEFAULT_FEEDERS, DOMAIN, MAX_SCHEDULES_PER_FEEDER

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
        return PetLibroOptionsFlowHandler()


class PetLibroOptionsFlowHandler(config_entries.OptionsFlow):
    """Handle PetLibro options sub-menu flow (Settings > Devices & Services > Configure)."""

    def __init__(self):
        # self.config_entry is a read-only property on the base OptionsFlow
        # (derived from self.handler once the flow manager initializes it) --
        # it must not be assigned here.
        self._selected_action = None
        self._selected_feeder = None
        self._selected_slot_id = None

    async def async_step_init(self, user_input=None):
        """Display sub-menu options for managing feeders, schedules, and collars."""
        return self.async_show_menu(
            step_id="init",
            menu_options=[
                "manage_schedules",
                "assign_collar",
                "delete_collar",
            ],
        )

    async def async_step_manage_schedules(self, user_input=None):
        """Pick which feeder's feeding times to manage, and whether it stays linked."""
        coordinator = self.hass.data[DOMAIN][self.config_entry.entry_id]
        feeder_names = [f["name"] for f in coordinator.feeders]
        default_feeder = feeder_names[0] if feeder_names else ""

        if user_input is not None:
            self._selected_feeder = user_input["feeder"]
            await coordinator.async_set_schedule_linked(self._selected_feeder, user_input["linked"])
            return await self.async_step_schedule_action()

        current_sched = coordinator.schedules.get(default_feeder, {})
        return self.async_show_form(
            step_id="manage_schedules",
            data_schema=vol.Schema({
                vol.Required("feeder", default=default_feeder): vol.In(feeder_names),
                vol.Optional("linked", default=current_sched.get("linked", True)): bool,
            }),
        )

    def _schedule_action_schema(self, slot_choices: dict) -> vol.Schema:
        schema = {
            vol.Required("action", default="add"): vol.In({
                "add": "Add a new feeding time",
                "edit": "Edit an existing feeding time",
                "delete": "Delete a feeding time",
            }),
        }
        if slot_choices:
            schema[vol.Optional("slot")] = vol.In(slot_choices)
        return vol.Schema(schema)

    async def async_step_schedule_action(self, user_input=None):
        """Show the selected feeder's current feeding times and choose add/edit/delete."""
        coordinator = self.hass.data[DOMAIN][self.config_entry.entry_id]
        sched = coordinator.schedules.get(self._selected_feeder, {})
        slots = sched.get("slots", [])
        slot_choices = {
            s["id"]: f"{s['time']} · {s['grain_num']} portion(s) · {'on' if s.get('enabled', True) else 'paused'}"
            for s in slots
        }

        if user_input is not None:
            action = user_input["action"]
            self._selected_slot_id = user_input.get("slot")

            if action == "add" and len(slots) >= MAX_SCHEDULES_PER_FEEDER:
                return self.async_show_form(
                    step_id="schedule_action",
                    data_schema=self._schedule_action_schema(slot_choices),
                    errors={"base": "max_schedules"},
                )
            if action in ("edit", "delete") and not self._selected_slot_id:
                return self.async_show_form(
                    step_id="schedule_action",
                    data_schema=self._schedule_action_schema(slot_choices),
                    errors={"base": "no_slot_selected"},
                )

            if action == "delete":
                await coordinator.async_delete_schedule_slot(self._selected_feeder, self._selected_slot_id)
                return self.async_create_entry(title="", data={})

            # add / edit both fall through to the same time/portions form.
            return await self.async_step_schedule_add_edit()

        return self.async_show_form(
            step_id="schedule_action",
            data_schema=self._schedule_action_schema(slot_choices),
            description_placeholders={"feeder": self._selected_feeder},
        )

    async def async_step_schedule_add_edit(self, user_input=None):
        """Set the time/portions/repeat days/enabled for the feeding time being added or edited."""
        coordinator = self.hass.data[DOMAIN][self.config_entry.entry_id]
        sched = coordinator.schedules.get(self._selected_feeder, {})
        slots = sched.get("slots", [])
        editing = next((s for s in slots if s["id"] == self._selected_slot_id), None)

        if user_input is not None:
            if editing:
                await coordinator.async_update_schedule_slot(
                    self._selected_feeder,
                    self._selected_slot_id,
                    time_str=user_input["time"],
                    grain_num=user_input["portions"],
                    repeat_day=user_input["repeat_day"],
                    enabled=user_input["enabled"],
                )
            else:
                await coordinator.async_add_schedule_slot(
                    self._selected_feeder,
                    time_str=user_input["time"],
                    grain_num=user_input["portions"],
                    repeat_day=user_input["repeat_day"],
                    enabled=user_input["enabled"],
                )
            return self.async_create_entry(title="", data={})

        defaults = editing or {"time": "08:00", "grain_num": 1, "repeat_day": "1111111", "enabled": True}
        data_schema = vol.Schema({
            vol.Required("time", default=defaults["time"]): str,
            vol.Optional("portions", default=defaults["grain_num"]): vol.All(vol.Coerce(int), vol.Range(min=1, max=10)),
            vol.Optional("repeat_day", default=defaults["repeat_day"]): str,
            vol.Optional("enabled", default=defaults.get("enabled", True)): bool,
        })

        return self.async_show_form(
            step_id="schedule_add_edit",
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
