# Deploys

Deploys go out from `main`, twice a day at most, never on Fridays after noon.

```sh
git tag v$(date +%Y.%m.%d) && git push --tags
lighthouse deploy --canary 10% --wait 15m
```

> [!CAUTION]
> A canary that pages during its 15 minutes rolls back automatically. Don't override it.
