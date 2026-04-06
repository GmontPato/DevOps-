# 🚀 Pasos para la Ejecución del Proyecto DevOps en AWS

## 1. Clonar el repositorio

```bash
git clone <https://github.com/GmontPCGamer/DevOps-.git>
cd "DevOps ev1"
```

---

## 2. Configurar AWS CLI

> Debe estar previamente instalado en el PC donde se vaya a probar. 
> Pedirá Access Key, Secret Key, Región y Formato (se obtiene de AWS Details).

```bash
aws configure
```

---

## 3. Inicializar Terraform

```bash
terraform init
```

---

## 4. Validar la configuración

```bash
terraform validate
```

---

## 5. Ver el plan de ejecución

```bash
terraform plan
```

---

## 6. Aplicar la infraestructura

> Pedirá una confirmación, se debe escribir `yes`

```bash
terraform apply
```

---

## 7. Verificar en la consola de AWS

- Que se haya creado la VPC, subredes, instancias EC2, NAT, etc.

---

## 8. Probar conectividad

- Obtener la IP pública de frontend (desde la consola AWS o salida de Terraform)
- Probar acceso por SSH o HTTP

---

## 9. Destruir la infraestructura al terminar

> Se escribe `yes` para confirmar destrucción

```bash
terraform destroy
```

---