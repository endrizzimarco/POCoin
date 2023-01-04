<script setup>
import axios from 'axios'
import { ref } from 'vue'

const poll_blockchain = async () => {
  return await (
    await axios.get('http://localhost:3000/get_blockchain?node=n1')
  ).data
}

const blockchain = ref({})
</script>

<template lang="pug">
.h-full.flex.flex-col
  p Blockchain component
  a-button(@click='testMethod') Test
</template>
