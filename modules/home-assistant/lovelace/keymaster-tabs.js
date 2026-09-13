const VIEW_OPTIONS = ["icon", "path", "theme", "visible"];

function errorCard(message) {
  return {
    type: "markdown",
    content: `## Keymaster Error\n\n${message}`,
  };
}

function lockTab(lock, metadata, cards, icon) {
  return {
    attributes: {
      label: metadata.title || lock.lock_name,
      icon,
    },
    card: {
      type: "vertical-stack",
      cards,
    },
  };
}

function fullWidthSlotCard(section) {
  if (section?.type !== "grid" || !Array.isArray(section.cards)) {
    return section;
  }

  return {
    type: "vertical-stack",
    cards: section.cards,
  };
}

function findEntity(config, predicate) {
  if (!config || typeof config !== "object") {
    return undefined;
  }
  if (Array.isArray(config)) {
    for (const value of config) {
      const entity = findEntity(value, predicate);
      if (entity) {
        return entity;
      }
    }
    return undefined;
  }
  if (typeof config.entity === "string" && predicate(config)) {
    return config.entity;
  }
  for (const value of Object.values(config)) {
    const entity = findEntity(value, predicate);
    if (entity) {
      return entity;
    }
  }
  return undefined;
}

function slotLabel(slot, section, hass) {
  const nameEntity = findEntity(section, (config) => config.name === "Name");
  const name = nameEntity ? hass.states?.[nameEntity]?.state?.trim() : "";
  if (!name || ["unknown", "unavailable"].includes(name.toLowerCase())) {
    return `Slot ${slot}`;
  }
  return `Slot ${slot}: ${name}`;
}

function panelCard(card) {
  return {
    type: "custom:mod-card",
    card,
    card_mod: {
      style: `
        ha-card {
          margin: 16px;
        }
      `,
    },
  };
}

class KeymasterTabsStrategy extends HTMLElement {
  static async generate(config, hass) {
    const title = config.title || "Keymaster";

    if (hass.config.state === "NOT_RUNNING") {
      return {
        title,
        type: "panel",
        cards: [{ type: "starting" }],
      };
    }

    let locks;
    try {
      locks = await hass.callWS({ type: "keymaster/list_locks" });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return { title, type: "panel", cards: [errorCard(message)] };
    }

    const lockTabs = [];
    for (const lock of [...locks].sort((a, b) => a.lock_name.localeCompare(b.lock_name))) {
      try {
        const metadata = await hass.callWS({
          type: "keymaster/get_view_metadata",
          config_entry_id: lock.entry_id,
        });
        const slotTabs = [];

        for (
          let slot = metadata.slot_start;
          slot < metadata.slot_start + metadata.slot_count;
          slot += 1
        ) {
          const section = await hass.callWS({
            type: "keymaster/get_section_config",
            config_entry_id: lock.entry_id,
            slot_num: slot,
          });
          slotTabs.push({
            attributes: { label: slotLabel(slot, section, hass) },
            card: fullWidthSlotCard(section),
          });
        }

        const cards = [];
        if (metadata.badges?.length) {
          cards.push({
            type: "grid",
            columns: 4,
            square: false,
            cards: metadata.badges,
          });
        }

        cards.push(
          slotTabs.length
            ? {
                type: "custom:tabbed-card",
                tabs: slotTabs,
              }
            : errorCard("No code slots are configured for this lock."),
        );
        lockTabs.push(lockTab(lock, metadata, cards, config.icon || "mdi:lock-smart"));
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        lockTabs.push(
          lockTab(lock, lock, [errorCard(message)], config.icon || "mdi:lock-smart"),
        );
      }
    }

    if (!lockTabs.length) {
      return {
        title,
        type: "panel",
        cards: [errorCard("No Keymaster locks found.")],
      };
    }

    const view = {
      title,
      type: "panel",
      cards: [panelCard({ type: "custom:tabbed-card", tabs: lockTabs })],
    };

    for (const option of VIEW_OPTIONS) {
      if (config[option] !== undefined) {
        view[option] = config[option];
      }
    }
    return view;
  }
}

for (const name of [
  "ll-strategy-view-keymaster-tabs",
  "ll-strategy-view-keymaster-tabs-view",
]) {
  if (!customElements.get(name)) {
    customElements.define(name, class extends KeymasterTabsStrategy {});
  }
}
