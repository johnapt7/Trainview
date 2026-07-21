# Trainview landing page

A dependency-free landing page and lightweight live board for Trainview.

## Run locally

From the repository root:

```sh
python3 -m http.server 8080 --directory website
```

Then open `http://localhost:8080`.

## Configure

Edit `config.js` before deploying:

- `API_BASE` points at the standalone backend's `/api` root.
- `APP_URL` is the App Store, universal, or custom-scheme link used by both calls to action.
- `DEFAULT_STATION` controls the first board a visitor sees.

The board URL stores its station and mode as query parameters, for example:

```text
/?station=EUS&mode=departures
```

Optional parameters preserve a more specific view:

- `callingAt=MAN` filters services to a destination or origin.
- `filter=on-time` or `filter=intercity` selects a service filter.
- `offset=30` opens the board 30 minutes ahead.

Saved stations are kept locally in the visitor's browser. Disruptions, rolling-stock details, carriage counts and calling points are read from the existing public API when available.

If the backend cannot be reached, the page deliberately falls back to clearly labelled preview data so the landing page remains presentable during local development. The backend must allow the deployed website's origin through CORS.
