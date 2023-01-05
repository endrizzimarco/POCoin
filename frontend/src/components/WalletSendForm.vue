<script setup>
import { ref } from 'vue'

const props = defineProps({
  available_balance: Number
})

const amount = ref(0)
const to_addr = ref(1)
</script>

<template lang="pug">
a-form(layout='inline')
  a-form-item
    a-input-number(
      v-model='amount',
      placeholder='Amount',
      :min='0',
      :max='props.available_balance',
      style='width: 100px'
    )
  a-form-item
    a-select(v-model='to_addr', placeholder='Address', style='width: 200px')
      a-select-opt-group
        template(#label)
          span Alice
        a-select-option(value='address1') address1
        a-select-option(value='address1') address2
      a-select-opt-group
        template(#label)
          span Bob
        a-select-option(value='address1') address1
        a-select-option(value='address1') address2
      a-select-opt-group
        template(#label)
          span Charlie
        a-select-option(value='address1') address1
        a-select-option(value='address1') address2
  a-form-item
    a-button Send
</template>
