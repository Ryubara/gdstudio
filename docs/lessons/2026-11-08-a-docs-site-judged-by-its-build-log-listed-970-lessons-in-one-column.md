---
areas: [process]
---
# A docs site judged by its build log listed 970 lessons in one column

2026-11-08

- **Saw:** the kit's site moved to Zensical (gdstudio #768, PR #789) with a clean strict build and every page counted,
  and its sidebar put all 970 lessons in one group that was always open: about 1,070 links and 450 KB on every page.
- **Cause:** the move kept `navigation.sections` from a site a tenth the size, and nobody looked at the built sidebar.
  A build log and a page count say every page is there; they say nothing about whether a reader can find one.
- **Fix:** topics are header tabs, sections fold and nest, `navigation.prune` sends only the open tab's tree (about 60
  links on a Godot page), the order comes from `.nav.yml` files and the lessons stay out of the nav (gdstudio #790).
  A change to a site, its theme or its nav is judged by captures of the built pages at desktop and phone width, with
  the biggest folder in view, and by the sidebar links a page carries; a test fails `navigation.sections`.
- **Docs:** [Docs site: the navigation](../studio/docs-site.md#nav).
