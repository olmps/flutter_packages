

TODO(matuella): Explain setup

```ts
export const appleSignInCallback = functions.https.onRequest((req, res) => {
  try {
    const body = new URLSearchParams(req.body).toString();
    const url = `intent://callback?${body}#Intent;package=${androidPackageId};scheme=signinwithapple;end`;
    res.redirect(url);
  } catch (validationError) {
    res.status(400).send('Malformed data in the request body');
  }
});
```