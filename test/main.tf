resource "random_pet" "this" {
  count = var.my_bool == true ? 1 : 0
}

output "pet" {
    value = random_pet.this[0].id
}

