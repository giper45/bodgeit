package com.thebodgeitstore.util;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

public final class DatabaseBootstrap {

    private DatabaseBootstrap() {
    }

    public static void initialize(Connection connection) throws SQLException {
        if (Database.tableExists(connection, "Products")) {
            return;
        }

        boolean autoCommit = connection.getAutoCommit();
        connection.setAutoCommit(false);
        try {
            createSchema(connection);
            seedData(connection);
            connection.commit();
        } catch (SQLException e) {
            connection.rollback();
            throw e;
        } finally {
            connection.setAutoCommit(autoCommit);
        }
    }

    private static void createSchema(Connection connection) throws SQLException {
        execute(connection, "CREATE TABLE ProductTypes (" +
            "typeid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "type varchar(50) NOT NULL, " +
            "CONSTRAINT UNIQUE_ProductTypes_type UNIQUE (type) )");

        execute(connection, "CREATE TABLE Products (" +
            "productid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "product varchar(50) NOT NULL, desc varchar(5000) NOT NULL, typeid INTEGER NOT NULL, price decimal NOT NULL, " +
            "CONSTRAINT UNIQUE_Products_product UNIQUE (product) )");

        execute(connection, "CREATE TABLE Users (" +
            "userid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "name varchar(100) NOT NULL, type varchar(10) NOT NULL, password varchar(30) NOT NULL, " +
            "currentbasketid INTEGER NULL, CONSTRAINT UNIQUE_Users_name UNIQUE (name) )");

        execute(connection, "CREATE TABLE Baskets (" +
            "basketid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "created TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL, userid INTEGER NULL)");

        execute(connection, "CREATE TABLE BasketContents (" +
            "bcid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "basketid INTEGER NOT NULL, productid INTEGER NOT NULL, quantity INTEGER NOT NULL, pricetopay decimal NOT NULL)");

        execute(connection, "CREATE TABLE Comments (" +
            "commentid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "name varchar(100) NULL, comment varchar(5000) NOT NULL, userid INTEGER NULL )");

        execute(connection, "CREATE TABLE f0ecfb32e56d3845f140e5c81a81363ce61d9d50 (" +
            "GOOD_JOB varchar(2) NULL)");

        execute(connection, "CREATE TABLE Score (" +
            "scoreid INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "task varchar(30) NOT NULL, description varchar(300) NOT NULL, status INTEGER NOT NULL, " +
            "CONSTRAINT UNIQUE_Score_label UNIQUE (task) )");
    }

    private static void seedData(Connection connection) throws SQLException {
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Widgets')");
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Thingies')");
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Thingamajigs')");
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Whatsits')");
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Gizmos')");
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Doodahs')");
        execute(connection, "INSERT INTO ProductTypes (type) VALUES ('Whatchamacallits')");

        insertProduct(connection, "Basic Widget", 1, "1.2");
        insertProduct(connection, "Complex Widget", 1, "3.1");
        insertProduct(connection, "Weird Widget", 1, "4.7");
        insertProduct(connection, "Thingie 1", 2, "3.0");
        insertProduct(connection, "Thingie 2", 2, "3.2");
        insertProduct(connection, "Thingie 3", 2, "3.3");
        insertProduct(connection, "Thingie 4", 2, "3.5");
        insertProduct(connection, "Thingie 5", 2, "3.7");
        insertProduct(connection, "TGJ AAA", 3, "0.9");
        insertProduct(connection, "TGJ ABB", 3, "1.4");
        insertProduct(connection, "TGJ CCC", 3, "0.7");
        insertProduct(connection, "TGJ CCD", 3, "2.2");
        insertProduct(connection, "TGJ EFF", 3, "3.0");
        insertProduct(connection, "TGJ GGG", 3, "2.6");
        insertProduct(connection, "TGJ HHI", 3, "2.1");
        insertProduct(connection, "TGJ JJJ", 3, "0.8");
        insertProduct(connection, "Whatsit called", 4, "4.1");
        insertProduct(connection, "Whatsit weigh", 4, "2.5");
        insertProduct(connection, "Whatsit feel like", 4, "3.95");
        insertProduct(connection, "Whatsit taste like", 4, "3.96");
        insertProduct(connection, "Whatsit sound like", 4, "2.9");
        insertProduct(connection, "GZ XT4", 5, "4.45");
        insertProduct(connection, "GZ ZX3", 5, "3.81");
        insertProduct(connection, "GZ FZ8", 5, "1.0");
        insertProduct(connection, "GZ K77", 5, "3.05");
        insertProduct(connection, "Zip a dee doo dah", 6, "3.99");
        insertProduct(connection, "Doo dah day", 6, "6.50");
        insertProduct(connection, "Bonzo dog doo dah", 6, "2.45");
        insertProduct(connection, "Tipofmytongue", 7, "3.74");
        insertProduct(connection, "Mindblank", 7, "1.00");
        insertProduct(connection, "Youknowwhat", 7, "4.32");
        insertProduct(connection, "Whatnot", 7, "2.68");

        execute(connection, "INSERT INTO Users (name, type, password) VALUES ('user1@thebodgeitstore.com', 'USER', '" + getRndPassword() + "')");
        execute(connection, "INSERT INTO Users (name, type, password) VALUES ('admin@thebodgeitstore.com', 'ADMIN', '" + getRndPassword() + "')");
        execute(connection, "INSERT INTO Users (name, type, password, currentbasketid) VALUES ('test@thebodgeitstore.com', 'USER', 'password', 1)");

        execute(connection, "INSERT INTO Baskets (userid) VALUES (3)");

        execute(connection, "INSERT INTO BasketContents (basketid, productid, quantity, pricetopay) VALUES (1, 1, 1, 1.1)");
        execute(connection, "INSERT INTO BasketContents (basketid, productid, quantity, pricetopay) VALUES (1, 3, 2, 2.1)");
        execute(connection, "INSERT INTO BasketContents (basketid, productid, quantity, pricetopay) VALUES (1, 5, 3, 1.5)");
        execute(connection, "INSERT INTO BasketContents (basketid, productid, quantity, pricetopay) VALUES (1, 7, 4, 0.95)");

        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('LOGIN_TEST', 'Login as test@thebodgeitstore.com', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('LOGIN_USER1', 'Login as user1@thebodgeitstore.com', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('LOGIN_ADMIN', 'Login as admin@thebodgeitstore.com', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('HIDDEN_ADMIN', 'Find hidden content as a non admin user', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('HIDDEN_DEBUG', 'Find diagnostic data', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('SIMPLE_XSS', 'Level 1: Display a popup using: &lt;script&gt;alert(\"XSS\")&lt;/script&gt;', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('XSS_USER', 'Level 2: Display a popup using: &lt;script&gt;alert(\"XSS\")&lt;/script&gt;', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('XSS_LOGIN', 'Level 3: Display a popup using: &lt;script&gt;alert(\"XSS\")&lt;/script&gt;', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('OTHER_BASKET', 'Access someone elses basket', -1)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('CSRF_BASKET', 'Force someone to add an item to their basket when they visit your webpage.', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('NEG_BASKET', 'Get the store to owe you money', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('PASSWD_GET', 'Change your password via a GET request', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('AES_XSS', 'Conquer AES encryption, and display a popup using: &lt;script&gt;alert(\"H@cked A3S\")&lt;/script&gt;', 0)");
        execute(connection, "INSERT INTO Score (task, description, status) VALUES ('AES_SQLI', 'Conquer AES encryption and append a list of table names to the normal results.', 0)");
    }

    private static void insertProduct(Connection connection, String product, int typeId, String price) throws SQLException {
        execute(connection, "INSERT INTO Products (product, desc, typeid, price) VALUES ('" +
            product + "', '" + getRndDesc() + "', " + typeId + ", " + price + ")");
    }

    private static String getRndPassword() {
        StringBuffer sb = new StringBuffer();
        int passwordSize = 5 + (int) (Math.random() * 10);
        for (int i = 0; i < passwordSize; i++) {
            int charValue = '0' + (int) (Math.random() * ('z' - '0'));
            sb.append((char) charValue);
        }
        return sb.toString();
    }

    private static String getRndDesc() {
        StringBuffer sb = new StringBuffer();
        int sentenceSize = 1 + (int) (Math.random() * 4);
        for (int i = 0; i < sentenceSize; i++) {
            addRndSentence(sb);
        }

        return sb.toString();
    }

    private static void addRndSentence(StringBuffer sb) {
        int wordSize = 4 + (int) (Math.random() * 20);
        addRndWord(sb, true);
        for (int i = 0; i < wordSize; i++) {
            sb.append(" ");
            addRndWord(sb, false);
        }
        sb.append(". ");
    }

    private static void addRndWord(StringBuffer sb, boolean capitalise) {
        int wordSize = (int) (Math.random() * 8);
        for (int i = 0; i < wordSize; i++) {
            int start = 'a';
            int end = 'z';
            if (capitalise && i == 0) {
                start = 'A';
                end = 'Z';
            }
            int charValue = start + (int) (Math.random() * (end - start));
            sb.append((char) charValue);
        }
    }

    private static void execute(Connection connection, String sql) throws SQLException {
        PreparedStatement stmt = null;
        try {
            stmt = connection.prepareStatement(sql);
            stmt.execute();
        } finally {
            if (stmt != null) {
                try {
                    stmt.close();
                } catch (Exception e) {
                }
            }
        }
    }
}
