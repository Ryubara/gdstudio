# References

Third-party models and images that agents build from live in `<workspace>/refs/`, never in a repository.

```sh
uv run --project python gds refs fetch https://poly.pizza/m/<id>                 # one model
uv run --project python gds refs fetch https://poly.pizza/bundle/<name>-<id>     # a whole bundle
```

| Writes | What |
| --- | --- |
| `refs/polypizza/<id>/model.glb`, `meta.json` | a model and the API's answer: title, creator, licence, attribution, triangles |
| `refs/polypizza/bundles/<id>/` | `bundle.json`, `index.json` (one row per model), `models/<id>/` as above |

Needs `POLY_PIZZA_API_KEY` in the environment (a free key from Poly Pizza; set it with `setx`, never in a file); the
key is never printed. An asset that moves into a game gets a licence entry built from its `meta.json`, and committing
it is a maintainer decision.
