const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../src/config/db');
const shop = require('../src/services/shopService');
const { items } = require('../src/services/runnerShopCatalog');

test('paid catalog has fixed server prices and is never granted as defaults', () => {
  assert.deepEqual(items.map(i=>i.price), [20,1000]);
  const fs=require('node:fs'), path=require('node:path');
  for(const i of items) assert.ok(fs.existsSync(path.resolve(__dirname,`../../frontend/assets/models/items/${i.code}.png`)));
});

test('real purchase service deducts, grants ownership, rejects repeat/insufficient funds, and rolls back errors', async t => {
  const original=db.getClient;t.after(()=>{db.getClient=original;});
  let coins=30;const owned=new Set();let failGrant=false;let locks=0;
  db.getClient=async()=>{
    let snapshot;
    return {release(){}, async query(sql,p=[]){
      if(sql==='BEGIN'){snapshot={coins,owned:new Set(owned)};locks=0;return{rows:[]};}
      if(sql==='ROLLBACK'){coins=snapshot.coins;owned.clear();snapshot.owned.forEach(i=>owned.add(i));return{rows:[]};}
      if(sql.includes('FOR UPDATE')){locks++;return{rows:[{coin_balance:coins,level:1,exp:0,exp_to_next:200}]};}
      if(sql.includes('WHERE l.id = $2')){
        assert.ok(locks>0,'ownership must be checked after wallet row lock');
        const item=items.find(i=>i.listingId===p[1]);
        return{rows:item?[{listing_id:item.listingId,item_id:item.id,price_coins:item.price,owned:owned.has(item.id),item_name:item.name,slot_code:'inner_top'}]:[]};
      }
      if(sql.includes('coin_balance = coin_balance -')){coins-=p[1];return{rows:[{coin_balance:coins,level:1,exp:0,exp_to_next:200}]};}
      if(sql.includes('INSERT INTO shop_purchases'))return{rows:[{id:'purchase-id',created_at:'now'}]};
      if(sql.includes('INSERT INTO user_avatar_items')){if(failGrant)throw new Error('database write failed');owned.add(p[1]);}
      return{rows:[]};
    }};
  };
  const result=await shop.purchase('user',items[0].listingId);
  assert.equal(result.progress.coinBalance,10);assert.ok(owned.has(items[0].id));
  await assert.rejects(shop.purchase('user',items[0].listingId),e=>e.statusCode===409);
  assert.equal(coins,10);
  await assert.rejects(shop.purchase('user',items[1].listingId),e=>e.statusCode===400);
  assert.equal(coins,10);assert.ok(!owned.has(items[1].id));
  coins=1200;failGrant=true;
  await assert.rejects(shop.purchase('user',items[1].listingId),/database write failed/);
  assert.equal(coins,1200);assert.ok(!owned.has(items[1].id));
  failGrant=false;
  const brown=await shop.purchase('user',items[1].listingId);
  assert.equal(brown.priceCoins,1000);assert.equal(coins,200);assert.ok(owned.has(items[1].id));
});

test('default shop query hides owned items only for its authenticated user', async t=>{
  const original=db.query;t.after(()=>{db.query=original;});
  db.query=async(sql,p)=>{
    if(!sql.includes('COUNT(*) OVER'))return{rows:[]};
    assert.equal(p[0],'buyer-only');
    assert.match(sql,/ui.user_id = \$1/);assert.match(sql,/ui.user_id IS NULL/);
    return{rows:[]};
  };
  await shop.listItems('buyer-only',{sort:'featured',limit:8,offset:0});
});
