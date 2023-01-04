<script setup>
import { ref } from 'vue'

const activeKey = ref('alice')
</script>

<template lang="pug">
.h-full.flex.flex-col
  a-tabs(v-model:activeKey='activeKey', type='card')
    a-tab-pane(key='alice', tab='Alice')
      a-card
        p Alice
    a-tab-pane(key='bob', tab='Bob')
      a-card
        p Bob
    a-tab-pane(key='charlie', tab='Charlie')
      a-card
        p Charlie
</template>
