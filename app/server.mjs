import express from 'express';
import oracledb from 'oracledb';
import session from 'express-session'
import fs from 'fs';
import multer from 'multer';
import methodOverride from 'method-override';
import bodyParser from 'body-parser';
const upload = multer({ dest: 'static/images/items/' });

const PORT = 3000;
const APP_TIMEOUT = 60 * 60 * 1000;
const EXPRESS_STATIC_DIR = 'static';
const DEFAULT_ITEM_IMAGE_NAME = 'default.png';
const ITEMS_XML_FILENAME = 'items.xml';
const CONNECT_STRING = 'localhost:1521/BGAMESSTORE';
const DB_CREDENTIALS_FILE_PATH = './db_credentials.json';

const CATALOG_VIEW = 'catalog.ejs';
const ITEM_VIEW = 'item.ejs';
const FAVS_VIEW = 'favs.ejs';
const CART_VIEW = 'cart.ejs';
const ORDERING_VIEW = 'ordering.ejs';
const ORDERS_VIEW = 'orders.ejs';
const ACCOUNT_VIEW = 'account.ejs';
const ERROR_VIEW = 'error.ejs';
const ADDITEM_VIEW = 'additem.ejs';
const UPDATEITEM_VIEW = 'updateitem.ejs';

const GUEST_DB_ROLENAME = 'GUESTROLE';
const CLIENT_DB_ROLENAME = 'CLIENTROLE';
const ADMIN_DB_ROLENAME = 'ADMINROLE';

const LOGIN_ALREADY_EXISTS_EXCEPTION = 'ORA-20001';
const CART_IS_EMPTY_EXCEPTION = 'ORA-20002';
const CART_CONTAINS_INVALID_ITEMS_EXCEPTION = 'ORA-20003';
const ACCOUNT_NOT_FOUND_EXCEPTION = 'ORA-20004';
const EXPORT_TO_XML_EXCEPTION  = 'ORA-20005';
const IMPORT_FROM_XML_EXCEPTION = 'ORA-20006';

let g_dbConnection = null;
let g_dbCredentials = getDbCredentials();
let g_idleTimeout = null;
resetIdleTimeout();
process.on('exit', exitHandler);
process.on('SIGINT', exitHandler);
process.on('SIGTERM', exitHandler);
process.on('uncaughtException', e => {
    console.error('Uncaught exception: ', e.stack);
    exitHandler()
});

let app = express();
app.use(session({
    secret: 'secret',
    resave: false,
    saveUninitialized: true
}));
app.use(express.static(EXPRESS_STATIC_DIR));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({extended: true}));
app.use(async (req, _res, next) => {
    resetIdleTimeout();
    if (!req.session.role) {
        await connectAs(GUEST_DB_ROLENAME, req);
        req.session.account_id = null;
    }
    next();
});

//========== PAGES ==========

app.get('/', (_req, res) => {
    res.redirect('/catalog');
});
app.get('/catalog', (req, res, next) => {
    let xml_error = req.session.xml_error;
    let xml_success = req.session.xml_success;
    req.session.xml_error = null;
    req.session.xml_success = null;
    try { authorize([GUEST_DB_ROLENAME, CLIENT_DB_ROLENAME, ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(CATALOG_VIEW, { ...req.session, xml_error, xml_success });
});
app.get('/item/:id', (req, res, next) => {
    try { authorize([GUEST_DB_ROLENAME, CLIENT_DB_ROLENAME, ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(ITEM_VIEW, { ...req.session, item_id: req.params.id });
});
app.get('/account', (req, res, next) => {
    let acc_error = req.session.acc_error;
    let acc_success = req.session.acc_success;
    req.session.acc_error = null;
    req.session.acc_success = null;
    try { authorize([GUEST_DB_ROLENAME, CLIENT_DB_ROLENAME, ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(ACCOUNT_VIEW, { ...req.session, acc_error, acc_success});
});
app.get('/add-item', (req, res, next) => {
    let ai_success = req.session.ai_success;
    let ai_error = req.session.ai_error;
    req.session.ai_success = null;
    req.session.ai_error = null;
    try { authorize([ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(ADDITEM_VIEW, { ...req.session, ai_error, ai_success });
});
app.get('/update-item/:id', (req, res, next) => {
    let ui_success = req.session.ui_success;
    let ui_error = req.session.ui_error;
    req.session.ui_success = null;
    req.session.ui_error = null;
    try { authorize([ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(UPDATEITEM_VIEW, { ...req.session, item_id: req.params.id, ui_success, ui_error });
});
app.get('/favs', (req, res, next) => {
    try { authorize([CLIENT_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(FAVS_VIEW, { ...req.session });
});
app.get('/cart', (req, res, next) => {
    try { authorize([CLIENT_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(CART_VIEW, { ...req.session });
});
app.get('/ordering', (req, res, next) => {
    try { authorize([CLIENT_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(ORDERING_VIEW, { ...req.session });
});
app.get('/orders', (req, res, next) => {
    try { authorize([CLIENT_DB_ROLENAME, ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(ORDERS_VIEW, { ...req.session });
});
app.get('/orders/:id', (req, res, next) => {
    try { authorize([CLIENT_DB_ROLENAME, ADMIN_DB_ROLENAME], req.session.role); } catch (e) { next(e); return; }
    res.render(ORDERS_VIEW, { ...req.session, order_id: req.params.id });
});

app.get('/stop', async (req, res) => {
    exitHandler();
});


//=======================
// API
//=======================

app.get('/api/catalog', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetCatalog(:cursor, :title, :publisher, :in_stock, :category, :ordering, :account_id); end;`,
            {
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
                title: req.query.f_title || null,
                publisher: req.query.f_publisher || null,
                in_stock: req.query.f_in_stock || 0,
                category: req.query.f_category || null,
                ordering: req.query.f_ordering || 'last_added',
                account_id: req.session.account_id || null
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.post('/api/export-items-to-xml', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.ExportItemsToXML(:filename); end;`,
            {
                filename: ITEMS_XML_FILENAME
            }
        );
        req.session.xml_success = 'Тавары паспяхова экспартаваныя!';
    } catch (e) {
        if (e.message.includes(EXPORT_TO_XML_EXCEPTION)) {
            req.session.xml_error = `Пры экспарце тавараў у XML адбылася памылка: ${e.message}`;
        } else {
            next(e);
            return;
        }
    }
    res.redirect('/catalog');
});
app.post('/api/import-items-from-xml', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.ImportItemsFromXML(:filename); end;`,
            {
                filename: ITEMS_XML_FILENAME
            }
        );
        req.session.xml_error = null;
        req.session.xml_success = 'Тавары паспяхова дададзеныя ў каталог!';
    } catch (e) {
        if (e.message.includes(IMPORT_FROM_XML_EXCEPTION)) {
            req.session.xml_success = null;
            req.session.xml_error = `Пры імпарце тавараў з XML адбылася памылка: ${e.message}`;
        } else {
            next(e);
            return;
        }
    }
    res.redirect('/catalog');
});
app.get('/api/get-item-info/:id', async (req, res, next) => {
    try {
        console.log(req.session.role);
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetItemInfo(:item_id, :account_id, :title, :price, :count, :image, :description, :category, :publisher, :year, :min_players, :max_players, :play_time, :player_min_age, :is_available, :is_in_favs, :is_in_cart); end;`,
            {
                item_id: req.params.id,
                account_id: req.session.account_id ?? 0,
                title: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                price: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                count: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                image: { dir: oracledb.BIND_OUT, type: oracledb.STRING },
                description: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                category: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                publisher: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                year: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                min_players: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                max_players: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                play_time: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                player_min_age: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                is_available: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                is_in_favs: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
                is_in_cart: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER }
            }
        );
        res.json({
            item_id: req.params.id,
            title: result.outBinds.title,
            price: result.outBinds.price,
            count: result.outBinds.count,
            image: result.outBinds.image,
            description: result.outBinds.description,
            category: result.outBinds.category,
            publisher: result.outBinds.publisher,
            year: result.outBinds.year,
            min_players: result.outBinds.min_players,
            max_players: result.outBinds.max_players,
            play_time: result.outBinds.play_time,
            player_min_age: result.outBinds.player_min_age,
            is_available: result.outBinds.is_available,
            is_in_favs: result.outBinds.is_in_favs,
            is_in_cart: result.outBinds.is_in_cart
        });
    } catch (e) {
        next(e);
    }
});
app.post('/api/toggle-in-favs/:id', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.ToggleItemInFavs(:account_id, :item_id, :is_in_favs); end;`,
            {
                account_id: req.session.account_id,
                item_id: req.params.id,
                is_in_favs: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_BOOLEAN }
            }
        );
        res.json({ isInFavs: result.outBinds.is_in_favs });
    } catch (e) {
        next(e);
    }
});
app.post('/api/toggle-in-cart/:id', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.ToggleItemInCart(:account_id, :item_id, :is_in_cart); end;`,
            {
                account_id: req.session.account_id,
                item_id: req.params.id,
                is_in_cart: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_BOOLEAN }
            }
        );
        res.json({ isInCart: result.outBinds.is_in_cart });
    } catch (e) {
        next(e);
    }
});
app.post('/api/sign-in', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.SignIn(:login, :password, :account_id, :rolename); end;`,
            {
                login: req.body.login,
                password: req.body.password,
                account_id: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_NUMBER },
                rolename: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 }
            }
        );
        await connectAs(result.outBinds.rolename, req);
        req.session.account_id = result.outBinds.account_id;
    } catch (e) {
        if (e.message.includes(ACCOUNT_NOT_FOUND_EXCEPTION)) {
            req.session.acc_error = 'Няправільны лагін або пароль!';
        } else {
            next(e);
            return;
        }
    }
    res.redirect('/account');
});
app.post('/api/sign-up', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.SignUpAsClient(:login, :password, :fullname, :email, :address, :account_id); end;`,
            {
                login: req.body.login,
                password: req.body.password,
                fullname: req.body.fullname,
                email: req.body.email,
                address: req.body.address,
                account_id: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_NUMBER }
            }
        );
        await connectAs(CLIENT_DB_ROLENAME, req);
        req.session.account_id = result.outBinds.account_id;
    } catch (e) {
        if (e.message.includes(LOGIN_ALREADY_EXISTS_EXCEPTION)) {
            req.session.acc_error = 'Ужо ёсць акаўнт з такім лагінам!';
        } else {
            next(e);
            return;
        }
    }
    res.redirect('/account');
});
app.post('/api/sign-out', async (req, res) => {
    await connectAs(GUEST_DB_ROLENAME, req);
    req.session.account_id = null;
    res.redirect('/account');
});
app.get('/api/get-account-info', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetAccountInfo(:id, :login, :fullname, :email); end;`,
            {
                id: req.session.account_id,
                login: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                fullname: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                email: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 }
            }
        );
        res.json({
            id: req.session.account_id,
            login: result.outBinds.login,
            fullname: result.outBinds.fullname,
            email: result.outBinds.email,
        });
    } catch (e) {
        next(e);
    }
});
app.post('/api/update-account-info', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.UpdateAccountInfo(:id, :login, :password, :fullname, :email); end;`,
            {
                id: req.session.account_id,
                login: req.body.login ?? null,
                password: req.body.password ?? null,
                fullname: req.body.fullname ?? null,
                email: req.body.email ?? null
            }
        );
        req.session.acc_success = 'Звесткі акаўнта абноўленыя!';
    } catch (e) {
        if (e.message.includes(LOGIN_ALREADY_EXISTS_EXCEPTION)) {
            req.session.acc_error = 'Ужо ёсць акаўнт з такім лагінам!';
        } else {
            next(e);
            return;
        }
    }
    res.redirect('/account');
});
app.get('/api/get-client-account-info', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetClientAccountInfo(:id, :address); end;`,
            {
                id: req.session.account_id,
                address: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 }
            }
        );
        res.json({
            id: req.session.account_id,
            address: result.outBinds.address
        });
    } catch(e) {
        next(e);
    }
});
app.post('/api/update-client-account-info', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.UpdateClientAccountInfo(:id, :address); end;`,
            {
                id: req.session.account_id,
                address: req.body.address ?? null
            }
        );
        req.session.acc_success = 'Кліенцкія звесткі абноўленыя!';
    } catch (e) {
        next(e);
        return;
    }
    res.redirect('/account');
});
app.post('/api/create-new-admin-account', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.CreateNewAdminAccount(:login, :password, :fullname, :email, :account_id); end;`,
            {
                login: req.body.login,
                password: req.body.password,
                fullname: req.body.fullname,
                email: req.body.email,
                account_id: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_NUMBER }
            }
        );
        req.session.acc_success = 'Новы адміністратар паспяхова дададзены!';
    } catch (e) {
        if (e.message.includes(LOGIN_ALREADY_EXISTS_EXCEPTION)) {
            req.session.acc_error = 'Ужо ёсць акаўнт з такім лагінам!';
        } else {
            next(e);
            return;
        }
    }
    res.redirect('/account');
});
app.post('/api/deactivate-account', async (req, res, next) => {
    try {
        if (req.session.role === ADMIN_DB_ROLENAME) {
            await dbExecute(req.session.role,
                `begin SYSADMIN.DeactivateAdminAccount(:id); end;`,
                {
                    id: req.session.account_id,
                }
            );
        } else if (req.session.role === CLIENT_DB_ROLENAME) {
            await dbExecute(req.session.role,
                `begin SYSADMIN.DeactivateClientAccount(:id); end;`,
                {
                    id: req.session.account_id,
                }
            );
        }
        await connectAs(GUEST_DB_ROLENAME, req);
        req.session.account_id = null;
        res.redirect('/account');
    } catch(e) {
        next(e);
    }
});
app.post('/api/add-item', upload.single('image'), async (req, res, next) => {
    try {
        let imagePath = '/images/items/';
        if (req.file) {
            imagePath += req.file.originalname;
            let staticPath = EXPRESS_STATIC_DIR + imagePath;
            if (fs.existsSync(staticPath)) {
                fs.unlinkSync(req.file.path);
            } else {
                fs.renameSync(req.file.path, staticPath);
            }
        } else {
            imagePath += DEFAULT_ITEM_IMAGE_NAME;
        }

        await dbExecute(req.session.role,
            `begin SYSADMIN.AddItem(:title, :price, :count, :image, :description, :category, :publisher, :year, :min_players, :max_players, :play_time, :player_min_age, :is_available, :id); end;`,
            {
                title: req.body.title,
                price: req.body.price,
                count: req.body.count,
                image: imagePath,
                description: req.body.description,
                category: req.body.category,
                publisher: req.body.publisher,
                year: req.body.year,
                min_players: req.body.min_players,
                max_players: req.body.max_players,
                play_time: req.body.play_time,
                player_min_age: req.body.player_min_age,
                is_available: req.body.is_available ? 1 : 0,
                id: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER }
            }
        );
        req.session.ai_success = 'Тавар паспяхова дададзены!';
    } catch (e) {
        req.session.ai_error = `Пры даданні тавара адбылася памылка: ${e.message}`; // next(e); return;
    }
    res.redirect('/add-item');
});
app.post('/api/update-item', upload.single('image'), async (req, res, next) => {
    try {
        let imagePath = null;
        if (req.file) {
            imagePath = `/images/items/${req.file.originalname}`;
            let staticPath = EXPRESS_STATIC_DIR + imagePath;
            if (fs.existsSync(staticPath)) {
                fs.unlinkSync(req.file.path);
            } else {
                fs.renameSync(req.file.path, staticPath);
            }
        }
        await dbExecute(req.session.role,
            `begin SYSADMIN.UpdateItem(:id, :title, :price, :count, :image, :description, :category, :publisher, :year, :min_players, :max_players, :play_time, :player_min_age, :is_available); end;`,
            {
                id: req.body.id,
                title: req.body.title ?? null,
                price: req.body.price ?? null,
                count: req.body.count ?? null,
                image: imagePath ?? null,
                description: req.body.description ?? null,
                category: req.body.category ?? null,
                publisher: req.body.publisher ?? null,
                year: req.body.year ?? null,
                min_players: req.body.min_players ?? null,
                max_players: req.body.max_players ?? null,
                play_time: req.body.play_time ?? null,
                player_min_age: req.body.player_min_age ?? null,
                is_available: req.body.is_available ? 1 : 0
            }
        );
        req.session.ui_error = null;
        req.session.ui_success = 'Тавар паспяхова абноўлены!';
    } catch(e) {
        req.session.ui_success = null;
        req.session.ui_error = `Пры абнаўленні тавара адбылася памылка: ${e.message}`;  // next(e); return;
    }
    res.redirect(`/update-item/${req.body.id}`);
});
app.get('/api/favs', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetFavsItems(:account_id, :cursor); end;`,
            {
                account_id: req.session.account_id,
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.post('/api/move-favs-to-cart', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.MoveFavsToCart(:account_id); end;`,
            {
                account_id: req.session.account_id
            }
        );
    } catch (e) {
        next(e);
        return;
    }
    res.redirect('/favs');
});
app.post('/api/clear-favs', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.ClearFavs(:account_id); end;`,
            {
                account_id: req.session.account_id
            }
        );
        res.redirect('/favs');
    } catch (e) {
        next(e);
    }
});
app.get('/api/cart', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetCartItems(:account_id, :cursor); end;`,
            {
                account_id: req.session.account_id,
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.get('/api/get-cart-cost', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetCartCost(:account_id, :cart_cost); end;`,
            {
                account_id: req.session.account_id,
                cart_cost: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_NUMBER }
            }
        );
        res.json({ cart_cost: result.outBinds.cart_cost });
    } catch (e) {
        next(e);
    }
});
app.post('/api/update-cart-item-count', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.UpdateCartItemCount(:account_id, :item_id, :cart_count); end;`,
            {
                account_id: req.session.account_id,
                item_id: req.body.item_id,
                cart_count: { val: req.body.cart_count, dir: oracledb.BIND_INOUT }
            }
        );
        res.json({ cart_count: result.outBinds.cart_count });
    } catch (e) {
        next(e);
    }
});
app.post('/api/clear-cart', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.ClearCart(:account_id); end;`,
            {
                account_id: req.session.account_id
            }
        );
        res.redirect('/cart');
    } catch (e) {
        next(e);
    }
});
app.post('/api/validate-cart', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.ValidateCart(:account_id); end;`,
            {
                account_id: req.session.account_id
            }
        );
        res.json({});
    } catch (e) {
        if (e.message.includes(CART_IS_EMPTY_EXCEPTION)) {
            res.json({ error: 'Кошык пусты!' });
        } else if (e.message.includes(CART_CONTAINS_INVALID_ITEMS_EXCEPTION)) {
            res.json({ error: 'У кошыку ёсць тавары не ў наяўнасці ці недаступныя тавары!' });
        } else {
            next(e);
        }
    }
});
app.post('/api/make-order', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.MakeOrder(:account_id, :comment, :card_number, :order_id); end;`,
            {
                account_id: req.session.account_id,
                comment: req.body.comment ?? '',
                card_number: req.body.card_number.replace(/\s/g, ''),
                order_id: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_NUMBER }
            }
        );
        res.redirect(`/orders/${result.outBinds.order_id}`);
    } catch (e) {
        if (e.message.includes(CART_IS_EMPTY_EXCEPTION)) {
            res.json({ error: 'Кошык пусты!' });
        } else if (e.message.includes(CART_CONTAINS_INVALID_ITEMS_EXCEPTION)) {
            res.json({ error: 'У кошыку ёсць тавары не ў наяўнасці ці недаступныя тавары!' });
        } else {
            next(e);
        }
    }
});
app.get('/api/get-client-orders-list', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetClientOrdersList(:account_id, :cursor); end;`,
            {
                account_id: req.session.account_id,
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.get('/api/get-all-orders-list', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetAllOrdersList(:cursor); end;`,
            {
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.get('/api/get-order-info/:id', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetOrderInfo(:order_id, :o_number, :o_date, :os_name, :o_comment, :o_cost, :oc_fullname, :oc_email, :oc_address, :o_card_number); end;`,
            {
                order_id: req.params.id,
                o_number: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                o_date : { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_DATE },
                os_name: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                o_comment: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                o_cost: { dir: oracledb.BIND_OUT, type: oracledb.DB_TYPE_NUMBER },
                oc_fullname: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                oc_email: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                oc_address: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 },
                o_card_number: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 32767 }
            }
        );
        res.json({
            order_id: req.params.id,
            order_number: result.outBinds.o_number,
            order_date : result.outBinds.o_date,
            os_name: result.outBinds.os_name,
            order_comment: result.outBinds.o_comment,
            order_cost: result.outBinds.o_cost,
            client_fullname: result.outBinds.oc_fullname,
            client_email: result.outBinds.oc_email,
            client_address: result.outBinds.oc_address,
            card_number: result.outBinds.o_card_number
        });
    } catch (e) {
        next(e);
    }
});
app.get('/api/get-order-items/:id', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetOrderItems(:order_id, :cursor); end;`,
            {
                order_id: req.params.id,
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.get('/api/get-client-orders-list', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetClientOrdersList(:account_id, :cursor); end;`,
            {
                account_id: req.session.account_id,
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.get('/api/get-order-statuses', async (req, res, next) => {
    try {
        const result = await dbExecute(req.session.role,
            `begin SYSADMIN.GetOrderStatuses(:cursor); end;`,
            {
                cursor: { dir: oracledb.BIND_OUT, type: oracledb.CURSOR },
            }
        );
        const resultSet = result.outBinds.cursor;
        const rows = [];
        let row;
        while (row = await resultSet.getRow()) {
            rows.push(row);
        }
        await resultSet.close();
        res.json(rows);
    } catch (e) {
        next(e);
    }
});
app.post('/api/set-order-status', async (req, res, next) => {
    try {
        await dbExecute(req.session.role,
            `begin SYSADMIN.SetOrderStatus(:order_id, :new_os_name); end;`,
            {
                order_id: req.body.order_id,
                new_os_name: req.body.new_os_name
            }
        );
        res.json({});
    } catch {
        next(e);
    }
});

//======================
app.use(methodOverride());
app.use((err, _req, res, next) => {
    console.error(err.stack);
    res.render(ERROR_VIEW, { error: err });
});

app.listen(PORT, () => {
    console.log(`App is listening on port ${PORT}...`);
})


//=======================
// APPLICATION UTILITIES
//=======================

function getDbCredentials() {
    return JSON.parse(
            fs.readFileSync(DB_CREDENTIALS_FILE_PATH, 'utf8')
        ).users;
}

async function connectToDbAs(rolename) {
    const kUserCreds = g_dbCredentials.find(cred => cred.rolename === rolename);
    if (!kUserCreds) {
        throw new Error(`Role ${rolename} not found in database credentials.`);
    }
    const kConfig = {
        username: kUserCreds.username,
        password: kUserCreds.password,
        connectString: CONNECT_STRING
    };
    if (g_dbConnection) {
        await g_dbConnection.close();
    }
    g_dbConnection = await oracledb.getConnection(kConfig);
    console.log(`Connected to database as ${kConfig.username} (${rolename}).`);
}

async function connectAs(rolename, req) {
    await connectToDbAs(rolename);
    req.session.role = rolename;
}

function exitHandler() {
    if (g_dbConnection) {
        g_dbConnection.close()
            .then(() => {
                console.log('Database connection closed successfully.');
                process.exit();
            }).catch(() => {
                console.log('Database connection closing failed.');
                process.exit(1);
            });
    }
    if (!process.exitTimeoutId) {
        process.exitTimeoutId = setTimeout(process.exit, 5000);
    }
}

function resetIdleTimeout() {
    if (g_idleTimeout) {
        clearTimeout(g_idleTimeout);
    }
    g_idleTimeout = setTimeout(() => {
      console.log(`No activity for ${APP_TIMEOUT / (60 * 1000)} minutes. Shutting down...`);
      exitHandler();
    }, APP_TIMEOUT);
}

async function dbExecute(rolename, sql, binds = [], opts = {}) {
    let result;
    try {
        result = await g_dbConnection.execute(sql, binds, opts);
    } catch (err) {
        console.log(sql);
        console.log(binds);
        console.log(opts);
        if (err.message.includes('ORA-03114')) {
            console.log(`Reconnecting to database...`);
            await connectToDbAs(rolename);
            result = await g_dbConnection.execute(sql, binds, opts);
        } else {
            g_dbConnection.rollback();
            throw err;
        }
    }
    g_dbConnection.commit();
    return result;
}

function authorize(allowedRoles, role) {
    if (!allowedRoles.includes(role)) {
        throw new Error('Вы не можаце праглядаць гэтую старонку!');
    }
}