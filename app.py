
import os
import socket
from decimal import Decimal, InvalidOperation

import pymysql
from flask import Flask, redirect, render_template, request

app = Flask(__name__)

def conectar_bd():
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ.get("DB_NAME", "cloudha"),
        port=3306,
        connect_timeout=5,
        cursorclass=pymysql.cursors.DictCursor
    )

@app.route("/health")
def health():
    return "OK", 200


@app.route("/")
def inicio():
    try:
        with conectar_bd() as conexion:
            with conexion.cursor() as cursor:
                cursor.execute(
                    "SELECT * FROM productos ORDER BY id DESC"
                )
                productos = cursor.fetchall()
    except Exception:
        app.logger.exception("Error de base de datos")
        return "No fue posible consultar MySQL", 503

    return render_template(
        "index.html",
        productos=productos,
        servidor=socket.gethostname()
    )

@app.route("/productos", methods=["POST"])
def guardar_producto():
    nombre = request.form.get("nombre", "").strip()

    try:
        precio = Decimal(request.form["precio"])
        existencia = int(request.form["existencia"])
    except (KeyError, ValueError, InvalidOperation):
        return "Datos inválidos", 400

    if (
        not nombre
        or len(nombre) > 120
        or not precio.is_finite()
        or precio < 0
        or precio > Decimal("99999999.99")
        or existencia < 0
    ):
        return "Datos inválidos", 400

    try:
        with conectar_bd() as conexion:
            with conexion.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO productos
                        (nombre, precio, existencia)
                    VALUES (%s, %s, %s)
                """, (nombre, precio, existencia))
            conexion.commit()
    except Exception:
        app.logger.exception("Error al guardar producto")
        return "No fue posible guardar el producto", 503

    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
