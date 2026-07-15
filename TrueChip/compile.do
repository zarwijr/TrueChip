# 1. Tạo thư viện work
vlib work
vmap work work

# 2. Compile tất cả các file
vlog -work work ./rtl/*.v
vlog -work work ./sim/*.v

echo "--- BIEN DICH XONG! ---"