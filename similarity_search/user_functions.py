"""Shared helpers for the similarity_search Markdown labs."""

import re

import oracledb
import pandas as pd


def display(value):
    """Render in a notebook, or print the underlying table in a Python shell."""
    try:
        from IPython import get_ipython
        from IPython.display import display as ipython_display
        if get_ipython() is not None:
            ipython_display(value)
            return
    except ImportError:
        pass
    print(getattr(value, "data", value))


def get_conn_cursor(user, password, dsn):
    conn = oracledb.connect(user=user, password=password, dsn=dsn)
    try:
        return conn, conn.cursor()
    except Exception:
        conn.close()
        raise


def read_lob(value):
    """Read a driver LOB while its connection is still open; preserve scalars."""
    return value.read() if isinstance(value, oracledb.LOB) else value


def get_db_version(cursor):
    return exec_sql(cursor, "SELECT product, version_full FROM product_component_version")


def exec_sql_rows(cursor, qry, bind_var=None):
    """Return raw rows. Read any LOB locators before closing the connection."""
    cursor.execute(qry, bind_var if bind_var is not None else {})
    return cursor.fetchall()


def exec_sql(cursor, qry, bind_var=None):
    """Return a DataFrame, materializing LOB values before another cursor call."""
    rows = exec_sql_rows(cursor, qry, bind_var)
    cols = [col[0] for col in cursor.description]
    values = [tuple(read_lob(value) for value in row) for row in rows]
    return pd.DataFrame(values, columns=cols)


def dml_sql(conn, cursor, sql, bind_var=None):
    """Execute DML and commit on success; roll back and propagate failures."""
    try:
        cursor.execute(sql, bind_var if bind_var is not None else {})
        affected = cursor.rowcount
        conn.commit()
        return affected
    except Exception:
        conn.rollback()
        raise


def ddl_sql(cursor, sql):
    """Execute DDL. Oracle DDL can implicitly commit the transaction."""
    cursor.execute(sql)


def clean_text2(value):
    """Normalize display whitespace while preserving meaningful punctuation."""
    value = read_lob(value)
    if value is None:
        return ""
    if not isinstance(value, str):
        return value
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", value)
    value = re.sub(r"[ \t]+", " ", value)
    return re.sub(r"\n{3,}", "\n\n", value).strip()


def clean_text(value):
    if isinstance(value, pd.DataFrame):
        result = value.copy()
        for name in result.columns:
            result[name] = result[name].map(
                lambda cell: clean_text2(cell) if isinstance(cell, str) else cell
            )
        return result
    return clean_text2(value)


def clean_text1(value):
    """Compatibility alias used by the original lab cells."""
    return clean_text(value)


def img_show(img):
    from PIL import Image
    import matplotlib.pyplot as plt
    with Image.open(img) as source:
        plt.figure(figsize=(5, 4))
        plt.imshow(source)
        plt.axis("off")
        plt.show()
