# Carbonite for 3.3.5a: a ChromieCraft player's changes

A fork of [anzz1/Carbonite-3.3.5](https://github.com/anzz1/Carbonite-3.3.5) (community patch 9), with changes made while playing on ChromieCraft (AzerothCore, WotLK 3.3.5a). They are on the `chromie` branch; `master` follows upstream.

The changes were made with AI coding assistants (Claude Code and Codex), and checked against mock tests and in game.

## Changes to Carbonite
- **Quest givers you can't take yet are purple.** A giver whose remaining quests you can't take yet gets a purple "!" (`Gfx\Map\IconExclaimP.tga`), and each such quest is purple in the tooltip with the reason, such as "(not yet: needs <quest>)".
  - The checks follow the server's rules: `Nx.NotYetRules` is built from AzerothCore's `quest_template_addon`, and `Nx.NotYetBlocked(id)` follows its `Player::CanTakeQuest`. That covers previous quests, exclusive groups, breadcrumbs, classes, max level and reputation.
  - Quests in your log don't keep a giver yellow.
- **Quests this character can never take are hidden.** That means another class, over the max level, an exclusive group already chosen, or a breadcrumb past its target. A giver left with only those (and done quests) drops off the map.
- **Nearby-enemy alerts can be filtered** by another addon: if one provides `Nx.Soc:ChromiePunkEligible(name)`, the nearby-enemy and marked-enemy chat lines and sounds only fire when it agrees. Without one, Carbonite behaves as before.
- **The CPU counters are left alone** while the global `ChromieAdaptiveFPSProfiling` is set, so an addon measuring CPU use over a window isn't reset by Carbonite's title line.

Known gaps: Carbonite's database has no minimum quest levels (every quest reads 0), and race and the server's conditions table aren't checked. Such quests still look available.

## QuestShare (new addon)
`QuestShare/` puts a **Share** button on Carbonite's quest window. Under the window, for the selected quest, it lists each party member: already on it, or why the server will refuse it (level, max level, class). After a share, it shows what each member's client answered, with refusals in red in the middle of the screen.

Its level, max-level and class checks read Carbonite's quest data and this fork's `Nx.NotYetRules`. With stock Carbonite it still shows who is already on the quest and what each member answered.

## Install
Copy the folders into `Interface\AddOns`.

## License
The upstream repository has no license file, and this fork doesn't add one. The changes are published here as a GitHub fork only.
