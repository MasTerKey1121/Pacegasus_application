// Generated fixture for the standalone visual smoke test. Production uses API ownership.
const fs = require('node:fs');
const path = require('node:path');
const { items } = require('../../backend/src/services/starterAvatarCatalog');
fs.writeFileSync(path.resolve(__dirname, '../../frontend/assets/models/starter_catalog.json'), JSON.stringify(items, null, 2));
const { items: paidItems } = require('../../backend/src/services/runnerShopCatalog');
fs.writeFileSync(path.resolve(__dirname, '../../frontend/assets/models/shop_catalog.json'), JSON.stringify(paidItems, null, 2));
